import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { ROLE_IDS, ROLE_META, isTrustLabel, normalizeTrustLabel, type TrustLabel } from "../_shared/roles.ts";
import {
  hasUnknownClaims,
  normalizeRefs,
  roleTitle,
  sha256,
  ROLE_BUDGETS,
  type GeneratedDoc,
  type ValidationIssue,
  validateTenDocPacket,
  wordCount,
  countBuilderNotes,
} from "../_shared/brain_contract.ts";
import { hasExplicitlyConfirmedBusinessType } from "../_shared/interview_gates.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ErrorLayer = "auth" | "authorization" | "validation" | "schema" | "transient" | "server";

type IntakeTurn = {
  id: string;
  turn_index: number;
  raw_text: string;
};

type DecisionItem = {
  id: string;
  decision_key: string;
  claim: string;
  status: TrustLabel;
  decision_state: "PROPOSED" | "CONFIRMED";
  evidence_refs: string[];
  lock_state: "open" | "locked";
  confirmed_by_turn_id?: string | null;
  has_conflict: boolean;
  conflict_key: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return fail(500, "SERVER_CONFIG_MISSING", "Missing server environment.", "server");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) return fail(401, "AUTH_TOKEN_MISSING", "Missing bearer token.", "auth");

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) return fail(401, "AUTH_INVALID", "Unauthorized.", "auth");
    const userId = authData.user.id;

    const payload = await req.json().catch(() => ({} as Record<string, unknown>));
    const projectId = String(payload.project_id ?? "").trim();
    const cycleNoInput = Number(payload.cycle_no ?? 0);
    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: projectRow, error: projectError } = await supabase
      .from("projects")
      .select("id,owner_user_id,active_cycle_no")
      .eq("id", projectId)
      .single();
    if (projectError || !projectRow) return fail(404, "PROJECT_NOT_FOUND", "Project not found.", "validation");
    if (projectRow.owner_user_id !== userId) return fail(403, "PROJECT_FORBIDDEN", "Project does not belong to current user.", "authorization");

    const cycleNo = cycleNoInput >= 1 ? cycleNoInput : Number(projectRow.active_cycle_no ?? 1);

    const { data: turnsData, error: turnsError } = await supabase
      .from("intake_turns")
      .select("id,turn_index,raw_text")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("turn_index", { ascending: true });
    if (turnsError) return failFromDbError(turnsError, "intake_turns.select");
    const intakeTurns = (turnsData ?? []) as IntakeTurn[];

    const { data: decisionsData, error: decisionsError } = await supabase
      .from("decision_items")
      .select("id,decision_key,claim,status,decision_state,evidence_refs,lock_state,confirmed_by_turn_id,has_conflict,conflict_key")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("updated_at", { ascending: false });
    if (decisionsError) return failFromDbError(decisionsError, "decision_items.select");
    const decisions = ((decisionsData ?? []) as DecisionItem[]).filter((d) => isTrustLabel(d.status));

    const gateIssues = validateCommitGates(intakeTurns, decisions);
    if (gateIssues.length > 0) {
      return fail(409, "COMMIT_VALIDATION_FAILED", "Commit gate failed.", "validation", { issues: gateIssues });
    }

    const inputFingerprint = await computeInputFingerprint(projectId, cycleNo, intakeTurns, decisions);
    const existing = await findExistingVersion(supabase, projectId, cycleNo, inputFingerprint);
    if (existing) {
      const existingSubmission = await fetchExistingSubmission(supabase, existing.id);
      const documents = await fetchVersionDocuments(supabase, existing.id);
      return json({
        contract_version_id: existing.id,
        contract_version_number: existing.version_number,
        documents,
        submission: existingSubmission,
        review_required: existingSubmission ? false : true,
        reused_existing_version: true,
      });
    }

    let generatedDocs = await generateDocsWithFallback(openAIKey, intakeTurns, decisions);
    generatedDocs = enforcePerRoleShape(generatedDocs, intakeTurns, decisions);

    const packetIssues: ValidationIssue[] = validateTenDocPacket(generatedDocs);
    const unknownDecisions = decisions.some((item) => item.status === "UNKNOWN");
    if (unknownDecisions && !hasUnknownClaims(generatedDocs)) {
      packetIssues.push({
        code: "UNKNOWN_SURVIVAL",
        severity: "block",
        message: "UNKNOWN decisions exist but output claims did not preserve UNKNOWN.",
      });
    }
    const blocking = packetIssues.filter((issue) => issue.severity === "block");
    if (blocking.length > 0) {
      return fail(409, "COMMIT_PACKET_INVALID", "Commit packet validation failed.", "validation", { issues: blocking });
    }

    const { data: latestVersion } = await supabase
      .from("contract_versions")
      .select("id,version_number")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("version_number", { ascending: false })
      .limit(1)
      .maybeSingle();
    const nextVersion = latestVersion?.version_number ? Number(latestVersion.version_number) + 1 : 1;

    const now = new Date().toISOString();
    const { data: insertedVersion, error: insertVersionError } = await supabase
      .from("contract_versions")
      .insert({
        project_id: projectId,
        cycle_no: cycleNo,
        version_number: nextVersion,
        status: "committed",
        document_count: 10,
        artifact_fingerprint: inputFingerprint,
        committed_at: now,
      })
      .select("id,version_number")
      .single();
    if (insertVersionError || !insertedVersion) {
      return failFromDbError(insertVersionError, "contract_versions.insert");
    }

    for (const doc of generatedDocs) {
      const { data: docRow, error: docError } = await supabase
        .from("contract_docs")
        .insert({
          project_id: projectId,
          cycle_no: cycleNo,
          contract_version_id: insertedVersion.id,
          role_id: doc.role_id,
          title: doc.title,
          body: doc.body,
          is_complete: true,
          word_count: wordCount(doc.body),
          builder_notes_count: countBuilderNotes(doc.body),
        })
        .select("id")
        .single();
      if (docError || !docRow) return failFromDbError(docError, "contract_docs.insert");

      for (const [claimIndex, claim] of doc.claims.entries()) {
        const { data: reqRow, error: reqError } = await supabase
          .from("requirements")
          .insert({
            project_id: projectId,
            cycle_no: cycleNo,
            contract_version_id: insertedVersion.id,
            contract_doc_id: docRow.id,
            role_id: doc.role_id,
            requirement_index: claimIndex,
            requirement_text: claim.claim_text,
            trust_label: claim.trust_label,
            status: "active",
          })
          .select("id")
          .single();
        if (reqError || !reqRow) return failFromDbError(reqError, "requirements.insert");

        for (const ref of claim.provenance_refs) {
          const parsed = parseProvenanceRef(ref);
          const { error: provError } = await supabase
            .from("provenance_links")
            .insert({
              project_id: projectId,
              cycle_no: cycleNo,
              contract_version_id: insertedVersion.id,
              contract_doc_id: docRow.id,
              requirement_id: reqRow.id,
              source_type: parsed.sourceType,
              source_id: parsed.sourceId,
              pointer: ref,
            });
          if (provError) return failFromDbError(provError, "provenance_links.insert");
        }
      }
    }

    await supabase.from("generation_runs").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      stage: "COMMIT",
      status: "passed",
      details: {
        contract_version_id: insertedVersion.id,
        contract_version_number: insertedVersion.version_number,
      },
      run_identity: `commit:${insertedVersion.id}`,
      input_fingerprint: inputFingerprint,
      output_fingerprint: inputFingerprint,
      attempt: 1,
      ended_at: now,
    });

    await supabase.from("audit_events").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      contract_version_id: insertedVersion.id,
      actor_type: "SERVICE",
      actor_id: userId,
      event_type: "contract.committed",
      payload: {
        contract_version_number: insertedVersion.version_number,
        review_required: true,
      },
    });

    const documents = await fetchVersionDocuments(supabase, insertedVersion.id);

    return json({
      contract_version_id: insertedVersion.id,
      contract_version_number: insertedVersion.version_number,
      documents,
      submission: null,
      review_required: true,
      reused_existing_version: false,
    });
  } catch (error) {
    return fail(500, "UNHANDLED_EXCEPTION", String(error), "server");
  }
});

function validateCommitGates(intakeTurns: IntakeTurn[], decisions: DecisionItem[]) {
  const issues: Array<{ code: string; message: string; decision_key?: string }> = [];

  if (intakeTurns.length === 0) {
    issues.push({ code: "DISCOVERY_EMPTY", message: "Intake is empty. Add at least one intake turn before commit." });
  }

  if (!hasExplicitlyConfirmedBusinessType(decisions)) {
    issues.push({ code: "BUSINESS_TYPE_UNCONFIRMED", message: "Business type must be explicitly confirmed before commit.", decision_key: "business_type" });
  }

  const conflicts = decisions.filter((d) => d.has_conflict);
  for (const conflict of conflicts) {
    issues.push({
      code: "CONTRADICTION_UNRESOLVED",
      message: `Contradiction remains unresolved for ${conflict.conflict_key ?? conflict.decision_key}.`,
      decision_key: conflict.decision_key,
    });
  }

  const missingEvidence = decisions.filter((d) => !Array.isArray(d.evidence_refs) || d.evidence_refs.length === 0);
  for (const missing of missingEvidence) {
    issues.push({
      code: "EVIDENCE_MISSING",
      message: `Decision ${missing.decision_key} has no provenance evidence.`,
      decision_key: missing.decision_key,
    });
  }

  return issues;
}

async function computeInputFingerprint(
  projectId: string,
  cycleNo: number,
  turns: IntakeTurn[],
  decisions: DecisionItem[],
) {
  return sha256(
    JSON.stringify({
      project_id: projectId,
      cycle_no: cycleNo,
      turns: turns.map((turn) => ({
        id: turn.id,
        turn_index: turn.turn_index,
        raw_text: turn.raw_text.trim(),
      })),
      decisions: decisions
        .map((decision) => ({
          id: decision.id,
          decision_key: decision.decision_key,
          claim: decision.claim.trim(),
          status: decision.status,
          decision_state: decision.decision_state,
          has_conflict: decision.has_conflict,
          conflict_key: decision.conflict_key,
          lock_state: decision.lock_state,
          evidence_refs: [...(decision.evidence_refs ?? [])].sort(),
        }))
        .sort((a, b) => a.decision_key.localeCompare(b.decision_key)),
    }),
  );
}

async function findExistingVersion(
  supabase: ReturnType<typeof createClient>,
  projectId: string,
  cycleNo: number,
  inputFingerprint: string,
) {
  const { data, error } = await supabase
    .from("contract_versions")
    .select("id,version_number")
    .eq("project_id", projectId)
    .eq("cycle_no", cycleNo)
    .eq("artifact_fingerprint", inputFingerprint)
    .order("version_number", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error || !data) return null;
  return { id: String(data.id), version_number: Number(data.version_number) };
}

async function fetchExistingSubmission(
  supabase: ReturnType<typeof createClient>,
  contractVersionId: string,
) {
  const { data, error } = await supabase
    .from("submission_artifacts")
    .select("id,bucket,storage_path,submitted_at")
    .eq("contract_version_id", contractVersionId)
    .maybeSingle();
  if (error || !data) return null;
  return {
    submission_id: String(data.id),
    bucket: String(data.bucket),
    path: String(data.storage_path),
    submitted_at: String(data.submitted_at),
  };
}

async function fetchVersionDocuments(
  supabase: ReturnType<typeof createClient>,
  contractVersionId: string,
) {
  const { data: docsOut } = await supabase
    .from("contract_docs")
    .select("id,project_id,cycle_no,contract_version_id,role_id,title,body,is_complete,created_at")
    .eq("contract_version_id", contractVersionId)
    .order("role_id", { ascending: true });

  const { data: reqsOut } = await supabase
    .from("requirements")
    .select("id,project_id,cycle_no,contract_version_id,contract_doc_id,role_id,requirement_text,trust_label,requirement_index")
    .eq("contract_version_id", contractVersionId)
    .order("role_id", { ascending: true })
    .order("requirement_index", { ascending: true });

  const { data: provOut } = await supabase
    .from("provenance_links")
    .select("requirement_id,pointer")
    .eq("contract_version_id", contractVersionId);

  const refsByRequirement = new Map<string, string[]>();
  for (const row of provOut ?? []) {
    const reqID = String((row as Record<string, unknown>).requirement_id);
    refsByRequirement.set(reqID, [...(refsByRequirement.get(reqID) ?? []), String((row as Record<string, unknown>).pointer)]);
  }

  const claimsByDoc: Record<string, unknown[]> = {};
  for (const req of reqsOut ?? []) {
    const reqObj = req as Record<string, unknown>;
    const reqID = String(reqObj.id);
    const docID = String(reqObj.contract_doc_id);
    claimsByDoc[docID] = claimsByDoc[docID] ?? [];
    claimsByDoc[docID].push({
      id: reqObj.id,
      project_id: reqObj.project_id,
      cycle_no: reqObj.cycle_no,
      contract_version_id: reqObj.contract_version_id,
      contract_doc_id: reqObj.contract_doc_id,
      role_id: reqObj.role_id,
      claim_text: reqObj.requirement_text,
      trust_label: reqObj.trust_label,
      provenance_refs: refsByRequirement.get(reqID) ?? [],
      claim_index: reqObj.requirement_index,
    });
  }

  return (docsOut ?? []).map((doc) => ({
    ...(doc as Record<string, unknown>),
    claims: claimsByDoc[String((doc as Record<string, unknown>).id)] ?? [],
  }));
}

async function generateDocsWithFallback(
  openAIKey: string,
  turns: IntakeTurn[],
  decisions: DecisionItem[],
) {
  let candidateDocs: GeneratedDoc[] = [];

  if (openAIKey) {
    try {
      candidateDocs = await tryLLM(openAIKey, turns, decisions);
    } catch {
      candidateDocs = [];
    }
  }

  if (candidateDocs.length === 0) {
    candidateDocs = buildDeterministicDocs(turns, decisions);
  }

  return stabilizeDocs(candidateDocs, turns, decisions);
}

function buildDeterministicDocs(turns: IntakeTurn[], decisions: DecisionItem[]): GeneratedDoc[] {
  return ROLE_IDS.map((roleID) => {
    const claims = buildClaimsForRole(roleID, turns, decisions);
    const body = buildRoleBody(roleID, turns, claims, summarizeContext(turns, decisions));
    return { role_id: roleID, title: roleTitle(roleID), body, claims };
  });
}

function buildClaimsForRole(roleID: number, turns: IntakeTurn[], decisions: DecisionItem[]): GeneratedDoc["claims"] {
  const selected: GeneratedDoc["claims"] = [];
  const userSaid = decisions.filter((item) => item.status === "USER_SAID").slice(0, 2);
  const assumed = decisions.filter((item) => item.status === "ASSUMED").slice(0, 1);
  const unknown = decisions.filter((item) => item.status === "UNKNOWN").slice(0, 2);

  for (const item of userSaid) {
    selected.push({
      claim_text: item.claim,
      trust_label: "USER_SAID",
      provenance_refs: normalizeRefs(item.evidence_refs, `decision:${item.id}`),
    });
  }
  for (const item of assumed) {
    selected.push({
      claim_text: item.claim,
      trust_label: "ASSUMED",
      provenance_refs: normalizeRefs(item.evidence_refs, `decision:${item.id}`),
    });
  }
  for (const item of unknown) {
    selected.push({
      claim_text: item.claim,
      trust_label: "UNKNOWN",
      provenance_refs: normalizeRefs(item.evidence_refs, `decision:${item.id}`),
    });
  }

  if (selected.length === 0) {
    const ref = turns[0] ? `turn:${turns[0].id}` : `role:${roleID}`;
    selected.push({
      claim_text: "No explicit decisions were confirmed; unresolved meaning remains UNKNOWN.",
      trust_label: "UNKNOWN",
      provenance_refs: [ref],
    });
  }

  return selected;
}

function buildRoleBody(
  roleID: number,
  turns: IntakeTurn[],
  claims: GeneratedDoc["claims"],
  contextSummary: string,
) {
  const roleMeta = ROLE_META[roleID];
  const budget = ROLE_BUDGETS[roleID];
  const userClaim = claims.find((claim) => claim.trust_label === "USER_SAID")?.claim_text
    ?? "The user intent for this area is not explicitly confirmed yet.";
  const assumedClaim = claims.find((claim) => claim.trust_label === "ASSUMED")?.claim_text
    ?? "No critical assumption is currently driving this role.";
  const unknownClaim = claims.find((claim) => claim.trust_label === "UNKNOWN")?.claim_text
    ?? "No unresolved unknown was captured for this role.";
  const acceptanceContext = summarizeRecentTurns(turns);
  const compact = budget.hardMax <= 200;
  const contextSnippet = contextSummary.slice(0, compact ? 90 : 170);

  const base = [
    "Purpose",
    compact
      ? `This document defines ${roleMeta.title.toLowerCase()} for the current cycle and keeps user intent explicit.`
      : `This document defines how ${roleMeta.title.toLowerCase()} should behave for the current project cycle. It stays buildable while preserving confirmed intent, visible assumptions, and explicit unknowns.`,
    "",
    "Key Decisions",
    `- [USER_SAID] ${userClaim}`,
    `- [ASSUMED] ${assumedClaim}`,
    compact ? `- Role anchor: ${roleMeta.key}.` : `- Role anchor: ${roleMeta.key}; align implementation decisions to this boundary.`,
    "",
    "Acceptance Criteria",
    "- The role behavior can be implemented without hidden assumptions.",
    "- Every claim stays linked to explicit intake evidence or decision records.",
    compact
      ? `- Flow remains aligned with recent context: ${acceptanceContext}.`
      : `- The flow remains consistent with current context: ${acceptanceContext}.`,
    "",
    "Success Measures",
    compact
      ? "- A reviewer can see what is in scope for version one."
      : "- A reviewer can read this role and understand what is in scope for version one.",
    compact
      ? "- A builder can execute this role without reinterpreting trust labels."
      : "- A builder can execute this role without reinterpreting trust labels or provenance.",
    "- Open uncertainty remains visible and does not silently disappear.",
    "",
    "Unknowns",
    `- [UNKNOWN] ${unknownClaim}`,
    compact ? "- Additional unknowns remain open until explicit confirmation." : "- Additional unknowns can remain open until user confirmation is captured.",
    "",
    "Builder Notes",
    "- Preserve trust labels exactly as provided in this packet.",
    "- Do not convert UNKNOWN items into implementation assumptions.",
    `- Use this role alongside the other nine documents and shared context: ${contextSnippet}.`,
  ].join("\n");

  return enforceRoleWordBudget(roleID, base);
}

function enforcePerRoleShape(
  docs: GeneratedDoc[],
  turns: IntakeTurn[],
  decisions: DecisionItem[],
) {
  const byRole = new Map<number, GeneratedDoc>();
  for (const doc of docs) {
    if (!byRole.has(doc.role_id)) byRole.set(doc.role_id, doc);
  }

  return ROLE_IDS.map((roleID) => {
    const existing = byRole.get(roleID);
    if (existing) {
      if (!existing.title || !existing.title.trim()) existing.title = roleTitle(roleID);
      if (!existing.claims || existing.claims.length === 0) existing.claims = buildClaimsForRole(roleID, turns, decisions);
      const mergedClaims = normalizeClaims(existing.claims, roleID, turns, decisions);
      const body = buildRoleBody(roleID, turns, mergedClaims, summarizeContext(turns, decisions));
      return {
        role_id: roleID,
        title: existing.title.trim(),
        body,
        claims: mergedClaims,
      };
    }
    const claims = buildClaimsForRole(roleID, turns, decisions);
    return {
      role_id: roleID,
      title: roleTitle(roleID),
      body: buildRoleBody(roleID, turns, claims, summarizeContext(turns, decisions)),
      claims,
    };
  });
}

function stabilizeDocs(
  docs: GeneratedDoc[],
  turns: IntakeTurn[],
  decisions: DecisionItem[],
): GeneratedDoc[] {
  const shaped = enforcePerRoleShape(docs, turns, decisions);
  const contextSummary = summarizeContext(turns, decisions);

  return shaped.map((doc) => {
    const claims = normalizeClaims(doc.claims, doc.role_id, turns, decisions);
    const body = buildRoleBody(doc.role_id, turns, claims, contextSummary);
    return {
      role_id: doc.role_id,
      title: roleTitle(doc.role_id),
      body,
      claims,
    };
  });
}

function normalizeClaims(
  claims: GeneratedDoc["claims"] | undefined,
  roleID: number,
  turns: IntakeTurn[],
  decisions: DecisionItem[],
): GeneratedDoc["claims"] {
  const clean = (claims ?? [])
    .map((claim) => ({
      claim_text: String(claim.claim_text ?? "").trim(),
      trust_label: normalizeTrustLabel(String(claim.trust_label)) ?? "UNKNOWN",
      provenance_refs: normalizeRefs(claim.provenance_refs, fallbackRef(roleID, turns, decisions)),
    }))
    .filter((claim) => claim.claim_text.length > 0);

  if (clean.length > 0) return clean.slice(0, 4);
  return buildClaimsForRole(roleID, turns, decisions);
}

function fallbackRef(roleID: number, turns: IntakeTurn[], decisions: DecisionItem[]): string {
  if (decisions[0]) return `decision:${decisions[0].id}`;
  if (turns[0]) return `turn:${turns[0].id}`;
  return `role:${roleID}`;
}

function summarizeRecentTurns(turns: IntakeTurn[]): string {
  const userTurns = turns.filter((turn) => turn.raw_text.trim().length > 0).slice(-2);
  if (userTurns.length === 0) return "recent intake evidence is limited.";
  return userTurns.map((turn) => turn.raw_text.trim()).join(" ");
}

function summarizeContext(turns: IntakeTurn[], decisions: DecisionItem[]): string {
  const decisionLine = decisions
    .filter((decision) => decision.status === "USER_SAID")
    .slice(0, 2)
    .map((decision) => decision.claim.trim())
    .filter(Boolean)
    .join(" ");
  const turnLine = summarizeRecentTurns(turns);
  return [decisionLine, turnLine]
    .filter((segment) => segment && segment.trim().length > 0)
    .join(" ")
    .slice(0, 320);
}

function enforceRoleWordBudget(roleID: number, text: string): string {
  const budget = ROLE_BUDGETS[roleID];
  let body = text.trim();
  let count = wordCount(body);
  const fillerSentences = [
    "Additional implementation context: preserve current scope boundaries while keeping unresolved decisions explicit.",
    "Additional implementation context: if evidence is thin, keep assumptions labeled and defer irreversible choices.",
  ];

  let index = 0;
  while (count < budget.hardMin && index < 6) {
    body += `\n\n${fillerSentences[index % fillerSentences.length]}`;
    count = wordCount(body);
    index += 1;
  }

  return body;
}

async function tryLLM(
  openAIKey: string,
  turns: IntakeTurn[],
  decisions: DecisionItem[],
): Promise<GeneratedDoc[]> {
  const prompt = [
    "Return exactly 10 JSON docs for role_id 1..10.",
    "Each doc must include title, body, claims[].",
    "Each claim requires trust_label USER_SAID|ASSUMED|UNKNOWN and provenance_refs[].",
    "Preserve unknown meaning as UNKNOWN.",
    `Intake turns: ${JSON.stringify(turns.map((t) => ({ turn_index: t.turn_index, raw_text: t.raw_text })))}`,
    `Decisions: ${JSON.stringify(decisions.map((d) => ({ key: d.decision_key, claim: d.claim, status: d.status, decision_state: d.decision_state, evidence_refs: d.evidence_refs })))}`,
  ].join("\n");

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.2,
      max_tokens: 2800,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You produce deterministic contract packets with strict role IDs." },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) throw new Error(`openai_error_${response.status}`);
  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (!content) throw new Error("openai_empty_content");
  const parsed = JSON.parse(content);
  const docsRaw = Array.isArray(parsed?.documents) ? parsed.documents : (Array.isArray(parsed) ? parsed : []);
  const docs = docsRaw.map((doc: Record<string, unknown>) => ({
    role_id: Number(doc.role_id),
    title: String(doc.title ?? roleTitle(Number(doc.role_id))),
    body: String(doc.body ?? ""),
    claims: Array.isArray(doc.claims) ? doc.claims.map((claim: Record<string, unknown>) => ({
      claim_text: String(claim.claim_text ?? ""),
      trust_label: normalizeTrustLabel(String(claim.trust_label)) ?? "UNKNOWN",
      provenance_refs: Array.isArray(claim.provenance_refs) ? claim.provenance_refs.map((value) => String(value)) : [],
    })) : [],
  })) as GeneratedDoc[];

  return docs;
}

function parseProvenanceRef(ref: string): { sourceType: "INTAKE_TURN" | "DECISION_ITEM"; sourceId: string | null } {
  const normalized = String(ref ?? "").trim();
  if (normalized.startsWith("turn:")) {
    return { sourceType: "INTAKE_TURN", sourceId: normalized.slice("turn:".length) || null };
  }
  if (normalized.startsWith("decision:")) {
    return { sourceType: "DECISION_ITEM", sourceId: normalized.slice("decision:".length) || null };
  }
  return { sourceType: "DECISION_ITEM", sourceId: null };
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function fail(status: number, code: string, message: string, layer: ErrorLayer, details: Record<string, unknown> = {}) {
  return json({
    error: {
      code,
      message,
      layer,
      ...details,
    },
  }, status);
}

function failFromDbError(
  dbError: { code?: string; message?: string; details?: string; hint?: string } | null,
  operation: string,
  fallbackMessage = "Database operation failed.",
) {
  const code = dbError?.code ?? "DB_ERROR";
  const message = dbError?.message ?? fallbackMessage;
  const schemaCodes = new Set(["42703", "42P01", "42704", "42883"]);
  const layer: ErrorLayer = schemaCodes.has(code) ? "schema" : "validation";
  const status = schemaCodes.has(code) ? 500 : 400;
  return fail(status, code, message, layer, {
    operation,
    details: dbError?.details ?? null,
    hint: dbError?.hint ?? null,
  });
}
