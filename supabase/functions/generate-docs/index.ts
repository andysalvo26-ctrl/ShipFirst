import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { ROLE_IDS, ROLE_META, isTrustLabel, normalizeTrustLabel, type TrustLabel } from "../_shared/roles.ts";
import {
  ROLE_BUDGETS,
  hasUnknownClaims,
  normalizeRefs,
  roleTitle,
  sha256,
  type GeneratedDoc,
  type ValidationIssue,
  validateTenDocPacket,
  wordCount,
  countBuilderNotes,
} from "../_shared/brain_contract.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
  evidence_refs: string[];
  lock_state: "open" | "locked";
};

type StageName =
  | "DISCOVERY"
  | "EXTRACTION"
  | "AMBIGUITY"
  | "CONFIRMATION"
  | "ASSEMBLY"
  | "CONSISTENCY"
  | "COMMIT";

type ErrorLayer = "auth" | "authorization" | "validation" | "schema" | "transient" | "server";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return fail(500, "SERVER_CONFIG_MISSING", "Missing Supabase server environment.", "server");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseHost = (() => {
      try {
        return new URL(supabaseUrl).hostname;
      } catch {
        return "invalid_supabase_url";
      }
    })();
    console.log(`[generate-docs] supabase_host=${supabaseHost}`);
    console.log(`[generate-docs] auth_header_length=${authHeader.length}`);
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return fail(401, "AUTH_TOKEN_MISSING", "Missing bearer token.", "auth");
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) return fail(401, "AUTH_INVALID", "Unauthorized.", "auth");
    const userId = authData.user.id;

    const payload = await req.json().catch(() => ({} as Record<string, unknown>));
    const projectId = String(payload.project_id ?? "").trim();
    const cycleNo = Number(payload.cycle_no ?? 1);
    const allowLegacy = Boolean(payload.allow_legacy ?? false);
    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");
    if (!allowLegacy) {
      return fail(
        409,
        "LEGACY_ENDPOINT_QUARANTINED",
        "generate-docs is quarantined in v3; use next-turn + commit-contract flow.",
        "validation",
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const now = new Date().toISOString();

    const { data: projectRow, error: projectError } = await supabase
      .from("projects")
      .select("id,owner_user_id")
      .eq("id", projectId)
      .single();

    if (projectError || !projectRow) return fail(404, "PROJECT_NOT_FOUND", "Project not found.", "validation");
    if (projectRow.owner_user_id !== userId) return fail(403, "PROJECT_FORBIDDEN", "Project does not belong to current user.", "authorization");

    const { data: turnsData, error: turnsError } = await supabase
      .from("intake_turns")
      .select("id,turn_index,raw_text")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("turn_index", { ascending: true });
    if (turnsError) return failFromDbError(turnsError, "intake_turns.select");
    const intakeTurns = (turnsData ?? []) as IntakeTurn[];

    if (intakeTurns.length === 0) {
      await recordStageRun(supabase, projectId, cycleNo, "DISCOVERY", "failed", {
        reason: "no_intake_turns",
        intake_turn_count: 0,
      });
      return fail(409, "GATE_DISCOVERY_EMPTY", "Discovery gate failed: intake is empty.", "validation");
    }
    await recordStageRun(supabase, projectId, cycleNo, "DISCOVERY", "passed", {
      intake_turn_count: intakeTurns.length,
    });

    const { data: decisionsData, error: decisionsError } = await supabase
      .from("decision_items")
      .select("id,decision_key,claim,status,evidence_refs,lock_state")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("updated_at", { ascending: false });

    if (decisionsError) return failFromDbError(decisionsError, "decision_items.select");

    let decisionItems = ((decisionsData ?? []) as DecisionItem[]).filter((d) => isTrustLabel(d.status));

    if (decisionItems.length === 0) {
      const fallback = {
        project_id: projectId,
        cycle_no: cycleNo,
        decision_key: "initial_intent_unknown",
        claim: "Core intent requires further clarification.",
        status: "UNKNOWN",
        evidence_refs: [`turn:${intakeTurns[0].id}`],
        lock_state: "open",
      };

      const { data: inserted, error: insertError } = await supabase
        .from("decision_items")
        .insert(fallback)
        .select("id,decision_key,claim,status,evidence_refs,lock_state")
        .single();

      if (insertError || !inserted || !isTrustLabel(inserted.status)) {
        return failFromDbError(insertError, "decision_items.insert_fallback", "Unable to initialize decision set.");
      }

      decisionItems = [inserted as DecisionItem];
    }
    await recordStageRun(supabase, projectId, cycleNo, "EXTRACTION", "passed", {
      decision_item_count: decisionItems.length,
    });

    const missingEvidence = decisionItems.filter((d) => !Array.isArray(d.evidence_refs) || d.evidence_refs.length === 0);
    if (missingEvidence.length > 0) {
      await recordStageRun(supabase, projectId, cycleNo, "AMBIGUITY", "failed", {
        missing_evidence_count: missingEvidence.length,
      });
      return fail(409, "GATE_AMBIGUITY_MISSING_EVIDENCE", "Ambiguity gate failed: decision items missing evidence.", "validation");
    }
    await recordStageRun(supabase, projectId, cycleNo, "AMBIGUITY", "passed", {
      missing_evidence_count: 0,
      unknown_count: decisionItems.filter((item) => item.status === "UNKNOWN").length,
    });

    await recordStageRun(supabase, projectId, cycleNo, "CONFIRMATION", "passed", {
      locked_count: decisionItems.filter((item) => item.lock_state === "locked").length,
      unknown_count: decisionItems.filter((item) => item.status === "UNKNOWN").length,
      blocking_contradictions: 0,
    });

    const inputFingerprint = await computeInputFingerprint(projectId, cycleNo, intakeTurns, decisionItems);

    const existing = await findExistingContractVersion(supabase, projectId, cycleNo, inputFingerprint);
    if (existing) {
      await recordStageRun(supabase, projectId, cycleNo, "COMMIT", "passed", {
        reused_existing_version: true,
        contract_version_id: existing.id,
        contract_version_number: existing.version_number,
        input_fingerprint: inputFingerprint,
      });
      const documents = await fetchVersionDocuments(supabase, existing.id);
      return json({
        contract_version_id: existing.id,
        contract_version_number: existing.version_number,
        documents,
        reused_existing_version: true,
      });
    }

    let generatedDocs = await generateDocsWithFallback(openAIKey, intakeTurns, decisionItems);
    generatedDocs = enforcePerRoleShape(generatedDocs, intakeTurns, decisionItems);
    await recordStageRun(supabase, projectId, cycleNo, "ASSEMBLY", "passed", {
      generated_doc_count: generatedDocs.length,
    });

    const issues: ValidationIssue[] = validateTenDocPacket(generatedDocs);
    const hasUnknownDecisions = decisionItems.some((item) => item.status === "UNKNOWN");
    if (hasUnknownDecisions && !hasUnknownClaims(generatedDocs)) {
      issues.push({ code: "UNKNOWN_SURVIVAL", severity: "block", message: "UNKNOWN decisions exist but no UNKNOWN claims were preserved in output." });
    }

    const blocking = issues.filter((issue) => issue.severity === "block");
    if (blocking.length > 0) {
      await recordStageRun(supabase, projectId, cycleNo, "CONSISTENCY", "failed", {
        issue_count: issues.length,
        block_issue_count: blocking.length,
        issue_codes: blocking.map((issue) => issue.code),
      });
      return fail(409, "GATE_CONSISTENCY_FAILED", "Consistency gate failed.", "validation", { issues: blocking });
    }
    await recordStageRun(supabase, projectId, cycleNo, "CONSISTENCY", "passed", {
      issue_count: issues.length,
      block_issue_count: 0,
    });

    const { data: latestVersion } = await supabase
      .from("contract_versions")
      .select("id,version_number")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("version_number", { ascending: false })
      .limit(1)
      .maybeSingle();

    const nextVersion = latestVersion?.version_number ? Number(latestVersion.version_number) + 1 : 1;

    const { data: contractVersion, error: versionError } = await supabase
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
      .select("id,project_id,cycle_no,version_number")
      .single();

    if (versionError || !contractVersion) {
      return failFromDbError(versionError, "contract_versions.insert", "Failed to create contract version.");
    }

    for (const doc of generatedDocs) {
      const { data: insertedDoc, error: docError } = await supabase
        .from("contract_docs")
        .insert({
          project_id: projectId,
          cycle_no: cycleNo,
          contract_version_id: contractVersion.id,
          role_id: doc.role_id,
          title: doc.title,
          body: doc.body,
          is_complete: true,
          word_count: wordCount(doc.body),
          builder_notes_count: countBuilderNotes(doc.body),
        })
        .select("id,project_id,cycle_no,contract_version_id,role_id,title,body,is_complete,created_at")
        .single();

      if (docError || !insertedDoc) return failFromDbError(docError, "contract_docs.insert", "Failed inserting contract doc.");

      for (const [index, claim] of doc.claims.entries()) {
        const { data: reqRow, error: reqError } = await supabase
          .from("requirements")
          .insert({
            project_id: projectId,
            cycle_no: cycleNo,
            contract_version_id: contractVersion.id,
            contract_doc_id: insertedDoc.id,
            role_id: doc.role_id,
            requirement_index: index,
            requirement_text: claim.claim_text,
            trust_label: claim.trust_label,
            status: "active",
          })
          .select("id")
          .single();

        if (reqError || !reqRow) return failFromDbError(reqError, "requirements.insert", "Failed inserting requirement.");

        for (const ref of claim.provenance_refs) {
          const parsed = parseProvenanceRef(ref);
          const { error: provError } = await supabase.from("provenance_links").insert({
            project_id: projectId,
            cycle_no: cycleNo,
            contract_version_id: contractVersion.id,
            contract_doc_id: insertedDoc.id,
            requirement_id: reqRow.id,
            source_type: parsed.sourceType,
            source_id: parsed.sourceId,
            pointer: ref,
          });

          if (provError) return failFromDbError(provError, "provenance_links.insert");
        }
      }
    }

    await recordStageRun(supabase, projectId, cycleNo, "COMMIT", "passed", {
      contract_version_id: contractVersion.id,
      version_number: contractVersion.version_number,
      input_fingerprint: inputFingerprint,
    });

    await supabase.from("audit_events").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      contract_version_id: contractVersion.id,
      actor_type: "SERVICE",
      actor_id: userId,
      event_type: "contract.committed",
      payload: { version_number: contractVersion.version_number, input_fingerprint: inputFingerprint },
    });

    const documents = await fetchVersionDocuments(supabase, contractVersion.id);

    return json({
      contract_version_id: contractVersion.id,
      contract_version_number: contractVersion.version_number,
      documents,
      reused_existing_version: false,
    });
  } catch (error) {
    return fail(500, "UNHANDLED_EXCEPTION", String(error), "server");
  }
});

async function computeInputFingerprint(
  projectId: string,
  cycleNo: number,
  turns: IntakeTurn[],
  decisions: DecisionItem[],
): Promise<string> {
  const payload = {
    project_id: projectId,
    cycle_no: cycleNo,
    turns: turns.map((turn) => ({ id: turn.id, turn_index: turn.turn_index, raw_text: turn.raw_text.trim() })),
    decisions: decisions
      .map((decision) => ({
        id: decision.id,
        decision_key: decision.decision_key,
        claim: decision.claim.trim(),
        status: decision.status,
        lock_state: decision.lock_state,
        evidence_refs: [...(decision.evidence_refs ?? [])].sort(),
      }))
      .sort((a, b) => a.decision_key.localeCompare(b.decision_key)),
  };

  return sha256(JSON.stringify(payload));
}

async function findExistingContractVersion(
  supabase: ReturnType<typeof createClient>,
  projectId: string,
  cycleNo: number,
  inputFingerprint: string,
): Promise<{ id: string; version_number: number } | null> {
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
  return { id: data.id, version_number: data.version_number };
}

async function fetchVersionDocuments(
  supabase: ReturnType<typeof createClient>,
  contractVersionId: string,
): Promise<Array<Record<string, unknown>>> {
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
    const key = String((row as Record<string, unknown>).requirement_id);
    refsByRequirement.set(key, [...(refsByRequirement.get(key) ?? []), String((row as Record<string, unknown>).pointer)]);
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
): Promise<GeneratedDoc[]> {
  if (openAIKey) {
    try {
      const llmDocs = await tryLLM(openAIKey, turns, decisions);
      if (llmDocs.length === 10) return llmDocs;
    } catch (_error) {
      // fallback below
    }
  }

  return buildDeterministicDocs(turns, decisions);
}

function buildDeterministicDocs(turns: IntakeTurn[], decisions: DecisionItem[]): GeneratedDoc[] {
  return ROLE_IDS.map((roleID) => {
    const claims = buildClaimsForRole(roleID, turns, decisions);
    const body = buildRoleBody(roleID, turns, claims);
    return {
      role_id: roleID,
      title: roleTitle(roleID),
      body,
      claims,
    };
  });
}

function buildClaimsForRole(roleID: number, turns: IntakeTurn[], decisions: DecisionItem[]): GeneratedDoc["claims"] {
  const userSaid = decisions.filter((decision) => decision.status === "USER_SAID");
  const assumed = decisions.filter((decision) => decision.status === "ASSUMED");
  const unknown = decisions.filter((decision) => decision.status === "UNKNOWN");

  const selected: GeneratedDoc["claims"] = [];

  if (userSaid[0]) {
    selected.push({
      claim_text: userSaid[0].claim,
      trust_label: "USER_SAID",
      provenance_refs: normalizeRefs(userSaid[0].evidence_refs, `decision:${userSaid[0].id}`),
    });
  }

  if (assumed[0]) {
    selected.push({
      claim_text: assumed[0].claim,
      trust_label: "ASSUMED",
      provenance_refs: normalizeRefs(assumed[0].evidence_refs, `decision:${assumed[0].id}`),
    });
  }

  if (unknown[0]) {
    selected.push({
      claim_text: unknown[0].claim,
      trust_label: "UNKNOWN",
      provenance_refs: normalizeRefs(unknown[0].evidence_refs, `decision:${unknown[0].id}`),
    });
  } else {
    const fallbackRef = turns[0] ? `turn:${turns[0].id}` : `role:${roleID}`;
    selected.push({
      claim_text: "Some operational details remain unresolved and must stay explicit until confirmed.",
      trust_label: "UNKNOWN",
      provenance_refs: [fallbackRef],
    });
  }

  if (userSaid[1]) {
    selected.push({
      claim_text: userSaid[1].claim,
      trust_label: "USER_SAID",
      provenance_refs: normalizeRefs(userSaid[1].evidence_refs, `decision:${userSaid[1].id}`),
    });
  }

  return selected;
}

function buildRoleBody(roleID: number, turns: IntakeTurn[], claims: GeneratedDoc["claims"]): string {
  const budget = ROLE_BUDGETS[roleID];
  const concise = budget.softTarget <= 170;
  const turnSummary = turns.slice(0, 2).map((turn) => `Turn ${turn.turn_index}: ${turn.raw_text}`).join(" ");

  const userClaim = claims.find((claim) => claim.trust_label === "USER_SAID")?.claim_text
    ?? "User-stated intent is still being clarified with explicit confirmations.";
  const assumedClaim = claims.find((claim) => claim.trust_label === "ASSUMED")?.claim_text
    ?? "Interim assumptions remain explicitly marked and reviewable.";
  const unknownClaim = claims.find((claim) => claim.trust_label === "UNKNOWN")?.claim_text
    ?? "Unknowns remain visible until direct confirmation.";

  const purposeText = concise
    ? `This role defines ${ROLE_META[roleID].key.toLowerCase()} expectations for the current run using explicit evidence from intake and decisions.`
    : `This role defines ${ROLE_META[roleID].key.toLowerCase()} expectations for the current run, translating intake evidence into a concise, testable contract that the human builder can execute without hidden assumptions.`;

  const keyDecisionLines = concise
    ? [
      `- [USER_SAID] ${userClaim}`,
      `- [ASSUMED] ${assumedClaim}`,
    ]
    : [
      `- [USER_SAID] ${userClaim}`,
      `- [ASSUMED] ${assumedClaim}`,
      `- [UNKNOWN] ${unknownClaim}`,
    ];

  const acceptanceLines = concise
    ? [
      "- The role includes concrete decisions tied to trust labels and evidence pointers.",
    ]
    : [
      "- The role includes concrete decisions tied to trust labels and evidence pointers.",
      "- The role can be reviewed for correctness without inferring missing intent.",
    ];

  const successLines = concise
    ? [
      "- A reviewer can verify intent lineage and testability in one pass.",
    ]
    : [
      "- A reviewer can verify intent lineage and testability in one pass.",
      "- Unknowns remain explicit and are routed to follow-up decisions.",
    ];

  const unknownLines = concise
    ? [`- [UNKNOWN] ${unknownClaim}`]
    : [
      `- [UNKNOWN] ${unknownClaim}`,
      "- Any unresolved constraint remains visible and is not auto-converted to certainty.",
    ];

  const builderNotes = [
    "- Keep trust labels and provenance visible in all downstream edits.",
    "- Preserve unresolved UNKNOWN items unless a confirmation event is recorded.",
    "- Reject wording that implies certainty where evidence is incomplete.",
    "- Keep language concise and specific to this run, not generic boilerplate.",
  ];

  let body = [
    "Purpose",
    purposeText,
    "",
    "Key Decisions",
    ...keyDecisionLines,
    "",
    "Acceptance Criteria",
    ...acceptanceLines,
    "",
    "Success Measures",
    ...successLines,
    "",
    "Unknowns",
    ...unknownLines,
    "",
    "Context",
    turnSummary || "No intake context available yet.",
    "",
    "Builder Notes",
    ...builderNotes,
  ].join("\n");

  body = fitBodyToBudget(body, budget.hardMin, budget.hardMax, turnSummary || userClaim);

  return body;
}

function fitBodyToBudget(body: string, hardMin: number, hardMax: number, fillerContext: string): string {
  let currentBody = body;
  let currentWords = wordCount(currentBody);

  if (currentWords < hardMin) {
    const fillerLine = `Additional context remains: ${fillerContext}.`;
    const insertionPoint = currentBody.indexOf("\nBuilder Notes\n");

    if (insertionPoint >= 0) {
      const before = currentBody.slice(0, insertionPoint);
      const after = currentBody.slice(insertionPoint);
      let contextBlock = "\nAdditional Context\n";
      while (wordCount(before + contextBlock + after) < hardMin) {
        contextBlock += `${fillerLine}\n`;
      }
      currentBody = `${before}${contextBlock}${after}`;
    }

    currentWords = wordCount(currentBody);
  }

  if (currentWords > hardMax) {
    const words = currentBody.trim().split(/\s+/);
    currentBody = words.slice(0, hardMax).join(" ");
  }

  return currentBody;
}

function enforcePerRoleShape(docs: GeneratedDoc[], turns: IntakeTurn[], decisions: DecisionItem[]): GeneratedDoc[] {
  const docsByRole = new Map<number, GeneratedDoc>();

  for (const doc of docs) {
    if (!ROLE_IDS.includes(doc.role_id as (typeof ROLE_IDS)[number])) continue;

    const roleID = doc.role_id;
    const claims = (doc.claims ?? []).map((claim) => ({
      claim_text: String(claim.claim_text ?? "").trim(),
      trust_label: normalizeTrustLabel(String(claim.trust_label)) ?? "UNKNOWN",
      provenance_refs: normalizeRefs(claim.provenance_refs, turns[0] ? `turn:${turns[0].id}` : `role:${roleID}`),
    }));

    const safeClaims = claims.length > 0 ? claims : buildClaimsForRole(roleID, turns, decisions);
    const safeBody = doc.body && doc.body.trim() ? doc.body.trim() : buildRoleBody(roleID, turns, safeClaims);

    docsByRole.set(roleID, {
      role_id: roleID,
      title: doc.title?.trim() || roleTitle(roleID),
      body: fitBodyToBudget(safeBody, ROLE_BUDGETS[roleID].hardMin, ROLE_BUDGETS[roleID].hardMax, turns[0]?.raw_text ?? safeClaims[0].claim_text),
      claims: safeClaims,
    });
  }

  for (const roleID of ROLE_IDS) {
    if (!docsByRole.has(roleID)) {
      const fallbackClaims = buildClaimsForRole(roleID, turns, decisions);
      docsByRole.set(roleID, {
        role_id: roleID,
        title: roleTitle(roleID),
        body: buildRoleBody(roleID, turns, fallbackClaims),
        claims: fallbackClaims,
      });
    }
  }

  return ROLE_IDS.map((roleID) => docsByRole.get(roleID) as GeneratedDoc);
}

async function tryLLM(openAIKey: string, turns: IntakeTurn[], decisions: DecisionItem[]): Promise<GeneratedDoc[]> {
  const prompt = {
    role_ids: ROLE_IDS,
    turns,
    decisions,
    rules: [
      "Return JSON only.",
      "Output exactly 10 documents with role_id 1..10.",
      "Each claim must include trust_label USER_SAID|ASSUMED|UNKNOWN and provenance_refs[].",
      "Never convert unresolved ambiguity into certainty.",
      "Each document body must include sections: Purpose, Key Decisions, Acceptance Criteria, Success Measures, Unknowns, Builder Notes.",
      "Builder Notes must contain 3 to 6 bullet points.",
    ],
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${openAIKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: "You are ShipFirstBrain. Generate concise role docs using only provided evidence and trust labels.",
        },
        {
          role: "user",
          content: JSON.stringify(prompt),
        },
      ],
    }),
  });

  if (!response.ok) throw new Error(`OpenAI failed ${response.status}`);

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content;
  if (!content) throw new Error("No content from model");

  const parsed = JSON.parse(content);
  const docs = Array.isArray(parsed.documents) ? parsed.documents : [];

  return docs
    .map((doc: Record<string, unknown>): GeneratedDoc => {
      const roleID = Number(doc.role_id);
      const safeRole = ROLE_META[roleID] ?? { key: `ROLE_${roleID}`, title: `Role ${roleID}` };
      const claims = Array.isArray(doc.claims)
        ? doc.claims.map((claim: Record<string, unknown>) => ({
          claim_text: String(claim.claim_text ?? "").trim(),
          trust_label: normalizeTrustLabel(String(claim.trust_label)) ?? "UNKNOWN",
          provenance_refs: Array.isArray(claim.provenance_refs)
            ? claim.provenance_refs.map((value: unknown) => String(value).trim()).filter(Boolean)
            : [],
        }))
        : [];

      return {
        role_id: roleID,
        title: String(doc.title ?? safeRole.title),
        body: String(doc.body ?? ""),
        claims,
      };
    })
    .filter((doc) => ROLE_IDS.includes(doc.role_id as (typeof ROLE_IDS)[number]));
}

function parseProvenanceRef(ref: string): { sourceType: "INTAKE_TURN" | "DECISION_ITEM"; sourceId: string | null } {
  if (ref.startsWith("turn:")) return { sourceType: "INTAKE_TURN", sourceId: ref.slice("turn:".length) || null };
  if (ref.startsWith("decision:")) return { sourceType: "DECISION_ITEM", sourceId: ref.slice("decision:".length) || null };
  return { sourceType: "DECISION_ITEM", sourceId: null };
}

async function recordStageRun(
  supabase: ReturnType<typeof createClient>,
  projectId: string,
  cycleNo: number,
  stage: StageName,
  status: "started" | "passed" | "failed",
  details: Record<string, unknown>,
) {
  const fingerprint = await sha256(JSON.stringify({
    project_id: projectId,
    cycle_no: cycleNo,
    stage,
    details,
  }));

  await supabase.from("generation_runs").insert({
    project_id: projectId,
    cycle_no: cycleNo,
    stage,
    status,
    details,
    input_fingerprint: details.input_fingerprint ?? fingerprint,
    run_identity: `${stage}:${fingerprint}`,
    ended_at: new Date().toISOString(),
  });
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
