import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { isTrustLabel, type TrustLabel } from "../_shared/roles.ts";
import { hasExplicitlyConfirmedBusinessType } from "../_shared/interview_gates.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ErrorLayer = "auth" | "authorization" | "validation" | "schema" | "transient" | "server";

type PostureMode = "Exploration" | "Artifact Grounding" | "Verification" | "Extraction" | "Alignment Checkpoint" | "Recovery";
type MoveType =
  | "MOVE_OPEN_DISCOVER"
  | "MOVE_REFLECT_VERIFY"
  | "MOVE_TARGETED_CLARIFY"
  | "MOVE_ALIGNMENT_CHECKPOINT"
  | "MOVE_SCOPE_REFRAME"
  | "MOVE_NUANCE_PROBE"
  | "MOVE_PRESERVE_UNKNOWN"
  | "MOVE_RECOVERY_RESET";
type BurdenSignal = "low" | "medium" | "high";
type PaceSignal = "opening" | "narrowing" | "reopening";

type IntakeTurn = {
  id: string;
  turn_index: number;
  raw_text: string;
  actor_type: "USER" | "SYSTEM";
};

type DecisionItem = {
  id: string;
  decision_key: string;
  claim: string;
  status: TrustLabel;
  evidence_refs: string[];
  lock_state: "open" | "locked";
  confirmed_by_turn_id?: string | null;
  has_conflict?: boolean;
  conflict_key?: string | null;
};

type Suggestion = {
  id: string;
  label: string;
};

type CheckpointStatus = "pending" | "confirmed" | "rejected" | "skipped";
type CheckpointAction = "confirm" | "reject" | "partial" | "skip";

type CheckpointResponseInput = {
  checkpoint_id?: string;
  action: CheckpointAction;
  optional_text?: string;
};

type CheckpointRow = {
  id: string;
  checkpoint_type: string;
  checkpoint_key: string;
  status: CheckpointStatus;
  payload: Record<string, unknown>;
};

type NextTurnCheckpoint = {
  id: string;
  type: string;
  status: CheckpointStatus;
  prompt: string;
  options: Suggestion[];
  requires_response: boolean;
};

type NextQuestionPlan = {
  assistant_message: string;
  suggestions: Suggestion[];
  why_question: string;
};

type ReadinessBucket = {
  key: string;
  label: string;
  status: "resolved" | "in_progress" | "missing";
  detail: string;
};

type ReadinessState = {
  score: number;
  resolved_count: number;
  total_count: number;
  next_focus: string;
  buckets: ReadinessBucket[];
};

type SignalState = {
  userTurnCount: number;
  richEvidenceCount: number;
  hasOpenEvidence: boolean;
};

type ControlState = {
  postureMode: PostureMode;
  moveType: MoveType;
  burdenSignal: BurdenSignal;
  paceSignal: PaceSignal;
  transitionReason: string;
};

type ArtifactInputRow = {
  id: string;
  artifact_type: string;
  artifact_ref: string;
  ingest_state: "pending" | "partial" | "complete" | "failed";
  verification_state: "unverified" | "user_confirmed" | "user_corrected";
  summary_text: string | null;
};

type ArtifactContext = {
  row: ArtifactInputRow | null;
  provenanceRefs: string[];
  statusMessage: string | null;
  ingestRunId: string | null;
  summaryId: string | null;
  summaryVersion: number | null;
  idempotencyKey: string | null;
};

type FetchOutcome = {
  status: "complete" | "partial" | "failed";
  canonicalUrl: string;
  httpStatus: number | null;
  contentType: string | null;
  extractedText: string;
  bytesRead: number;
  truncated: boolean;
  errorCode: string | null;
  errorMessage: string | null;
};

type LatestSummaryMeta = {
  summaryId: string;
  summaryText: string;
  summaryVersion: number;
  ingestRunId: string | null;
  provenanceRefs: string[];
};

const INGESTION_LIMITS_VERSION = "sync-v1";
const MAX_REDIRECTS = 3;
const FETCH_TIMEOUT_MS = 8000;
const MAX_FETCH_BYTES = 1_000_000;
const MIN_EXTRACT_CHARS = 80;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    const brainVersion = Deno.env.get("SHIPFIRST_BRAIN_VERSION") ?? "shipfirst-brain-v3";

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return fail(500, "SERVER_CONFIG_MISSING", "Missing Supabase server environment.", "server");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseHost = safeHost(supabaseUrl);
    console.log(`[next-turn] supabase_host=${supabaseHost}`);
    console.log(`[next-turn] auth_header_length=${authHeader.length}`);

    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return fail(401, "AUTH_TOKEN_MISSING", "Missing bearer token.", "auth");
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) {
      return fail(401, "AUTH_INVALID", "Unauthorized.", "auth");
    }
    const userId = authData.user.id;

    const payload = await req.json().catch(() => ({} as Record<string, unknown>));
    const projectId = String(payload.project_id ?? "").trim();
    const cycleNoInput = Number(payload.cycle_no ?? 0);
    const userMessageRaw = String(payload.user_message ?? "").trim();
    const selectedOptionId = String(payload.selected_option_id ?? "").trim();
    const noneFitText = String(payload.none_fit_text ?? "").trim();
    const checkpointResponseInput = normalizeCheckpointResponseInput(payload.checkpoint_response, selectedOptionId, noneFitText);
    const lastQuestionId = String(payload.last_question_id ?? "").trim();
    const providedArtifactRef = String(payload.artifact_ref ?? "").trim();
    const artifactTypeRaw = String(payload.artifact_type ?? "website").trim();
    const forceRefresh = Boolean(payload.force_refresh ?? false);
    const correlationId = String(payload.correlation_id ?? crypto.randomUUID()).trim();

    if (!projectId) {
      return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: projectRow, error: projectError } = await serviceClient
      .from("projects")
      .select("id,owner_user_id,active_cycle_no")
      .eq("id", projectId)
      .single();

    if (projectError || !projectRow) {
      return fail(404, "PROJECT_NOT_FOUND", "Project not found.", "validation");
    }
    if (projectRow.owner_user_id !== userId) {
      return fail(403, "PROJECT_FORBIDDEN", "Project does not belong to current user.", "authorization");
    }

    const cycleNo = cycleNoInput >= 1 ? cycleNoInput : Number(projectRow.active_cycle_no ?? 1);
    if (cycleNoInput >= 1 && Number(projectRow.active_cycle_no ?? 1) < cycleNoInput) {
      await serviceClient.from("projects").update({ active_cycle_no: cycleNoInput }).eq("id", projectId);
    }

    const resolvedText = resolveUserText(userMessageRaw, selectedOptionId, noneFitText);
    const autoUrl = extractFirstUrl(resolvedText || userMessageRaw || noneFitText);
    const artifactRef = providedArtifactRef || autoUrl || "";

    if (!resolvedText && !selectedOptionId && !artifactRef) {
      return fail(400, "USER_MESSAGE_REQUIRED", "Provide user_message, selected_option_id, or artifact_ref.", "validation");
    }

    console.log(`[next-turn] project_id=${projectId} cycle_no=${cycleNo} user_id=${userId} has_last_question_id=${lastQuestionId.length > 0}`);

    const { data: latestTurnRows, error: latestTurnError } = await serviceClient
      .from("intake_turns")
      .select("id,turn_index")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("turn_index", { ascending: false })
      .limit(1);
    if (latestTurnError) return failFromDbError(latestTurnError, "intake_turns.select_latest");
    const nextTurnIndex = (latestTurnRows?.[0]?.turn_index ?? 0) + 1;

    const userTurnInsert = await insertTurn(serviceClient, {
      projectId,
      cycleNo,
      turnIndex: nextTurnIndex,
      actorType: "USER",
      rawText: resolvedText || `selection:${selectedOptionId || "none"}`,
    });
    if ("error" in userTurnInsert) return userTurnInsert.error;

    if (resolvedText.trim().length > 0) {
      await upsertSemanticEntryForTurn(serviceClient, {
        openAIKey,
        projectId,
        cycleNo,
        turnId: userTurnInsert.row.id,
        sourceText: resolvedText,
        brainVersion,
      });
    }

    const artifactContextResult = await processArtifactContext(serviceClient, {
      projectId,
      cycleNo,
      userTurnId: userTurnInsert.row.id,
      artifactRef,
      artifactTypeRaw,
      selectedOptionId,
      noneFitText,
      forceRefresh,
      openAIKey,
      brainVersion,
      correlationId,
    });
    if ("error" in artifactContextResult) return artifactContextResult.error;
    let artifactContext = artifactContextResult.data;

    const checkpointResult = await resolveOrCreateCheckpoint(serviceClient, {
      projectId,
      cycleNo,
      userTurnId: userTurnInsert.row.id,
      artifactContext,
      checkpointResponseInput,
      userText: resolvedText,
      brainVersion,
    });
    if ("error" in checkpointResult) return checkpointResult.error;
    const activeCheckpoint = checkpointResult.data.checkpoint;
    artifactContext = checkpointResult.data.artifactContext;

    const { data: recentTurnsData, error: recentTurnsError } = await serviceClient
      .from("intake_turns")
      .select("id,turn_index,raw_text,actor_type")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("turn_index", { ascending: false })
      .limit(12);
    if (recentTurnsError) return failFromDbError(recentTurnsError, "intake_turns.select_recent");

    const recentTurns = ((recentTurnsData ?? []) as IntakeTurn[]).reverse();

    const { data: decisionRows, error: decisionError } = await serviceClient
      .from("decision_items")
      .select("id,decision_key,claim,status,evidence_refs,lock_state,confirmed_by_turn_id")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("updated_at", { ascending: false });
    if (decisionError) return failFromDbError(decisionError, "decision_items.select");

    const priorDecisions = ((decisionRows ?? []) as DecisionItem[]).filter((row) => isTrustLabel(row.status));

    const checkpointPending = activeCheckpoint?.status === "pending";

    const signalState = buildSignalState(recentTurns);

    await upsertMeaningMarkers(serviceClient, {
      projectId,
      cycleNo,
      userTurnId: userTurnInsert.row.id,
      userText: resolvedText,
      selectedOptionId,
      noneFitText,
      priorDecisions,
      artifactVerificationPending: checkpointPending,
    });

    const { data: latestDecisionRows, error: latestDecisionError } = await serviceClient
      .from("decision_items")
      .select("id,decision_key,claim,status,lock_state,confirmed_by_turn_id,has_conflict,conflict_key")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("updated_at", { ascending: false });
    if (latestDecisionError) return failFromDbError(latestDecisionError, "decision_items.select_latest");

    const latestDecisions = ((latestDecisionRows ?? []) as DecisionItem[]).filter((row) => isTrustLabel(String(row.status)));

    let questionPlan: NextQuestionPlan;
    let controlState: ControlState;

    if (checkpointPending && activeCheckpoint) {
      questionPlan = buildPendingCheckpointPlan(activeCheckpoint);
      controlState = {
        postureMode: "Artifact Grounding",
        moveType: "MOVE_REFLECT_VERIFY",
        burdenSignal: "low",
        paceSignal: "opening",
        transitionReason: "pending_checkpoint_requires_response",
      };
    } else if (artifactContext.row && artifactContext.row.verification_state === "unverified") {
      questionPlan = {
        assistant_message: "I still need a quick verification response before we narrow decisions.",
        suggestions: [],
        why_question: "artifact_checkpoint_required",
      };
      controlState = {
        postureMode: "Artifact Grounding",
        moveType: "MOVE_REFLECT_VERIFY",
        burdenSignal: "low",
        paceSignal: "opening",
        transitionReason: "artifact_requires_comprehension_verification",
      };
    } else {
      questionPlan = await buildNextQuestionPlan({
        recentTurns,
        decisions: latestDecisions,
        latestUserText: resolvedText || selectedOptionId || "",
        selectedOptionId,
      });
      controlState = deriveControlState({
        selectedOptionId,
        suggestionsCount: questionPlan.suggestions.length,
        unresolvedCount: ((latestDecisionRows ?? []) as Array<Record<string, unknown>>).filter((row) => String(row.status) === "UNKNOWN").length,
      });
      controlState.transitionReason = questionPlan.why_question;
    }
    questionPlan = sanitizeQuestionPlan(questionPlan);

    const assistantTurnInsert = await insertTurn(serviceClient, {
      projectId,
      cycleNo,
      turnIndex: nextTurnIndex + 1,
      actorType: "SYSTEM",
      rawText: questionPlan.assistant_message,
    });
    if ("error" in assistantTurnInsert) return assistantTurnInsert.error;

    const { error: turnStateError } = await serviceClient.from("interview_turn_state").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      turn_id: assistantTurnInsert.row.id,
      posture_mode: controlState.postureMode,
      move_type: controlState.moveType,
      burden_signal: controlState.burdenSignal,
      pace_signal: controlState.paceSignal,
      transition_reason: controlState.transitionReason,
    });
    if (turnStateError) return failFromDbError(turnStateError, "interview_turn_state.insert");

    const unresolved = ((latestDecisionRows ?? []) as Array<Record<string, unknown>>)
      .filter((row) => {
        const isConflict = Boolean(row.has_conflict);
        return String(row.status) === "UNKNOWN" || String(row.lock_state) === "open" || isConflict;
      })
      .map((row) => {
        const id = String(row.id);
        return {
          id,
          pointer: `decision_item:${id}`,
          decision_key: String(row.decision_key ?? ""),
          claim: String(row.claim ?? ""),
          status: String(row.status ?? "UNKNOWN"),
          decision_state: String(row.lock_state ?? "open") === "locked" ? "CONFIRMED" : "PROPOSED",
          has_conflict: Boolean(row.has_conflict),
          conflict_key: row.conflict_key ? String(row.conflict_key) : null,
        };
      });

    if (checkpointPending && artifactContext.row) {
      unresolved.push({
        id: artifactContext.row.id,
        pointer: `artifact_input:${artifactContext.row.id}`,
        decision_key: "artifact_verification",
        claim: artifactContext.statusMessage ?? "Artifact understanding is not verified yet.",
        status: "UNKNOWN",
        decision_state: "PROPOSED",
        has_conflict: false,
        conflict_key: null,
      });
    }

    const coreReady = hasCommitReadiness(latestDecisionRows ?? [], checkpointPending);
    const qualityReady = hasQualityReadiness(coreReady, signalState, latestDecisionRows ?? []);
    const canCommit = coreReady && qualityReady;
    const qualityBoostAvailable = canCommit && signalState.richEvidenceCount < 5;
    const qualityHint = canCommit
      ? (qualityBoostAvailable ? "You can generate now, or answer one more quick question to strengthen the draft." : "Signal quality is strong for draft generation.")
      : (coreReady ? "Answer a couple more plain-language questions so the draft has enough real detail." : null);
    const commitBlockers = collectCommitBlockers(latestDecisionRows ?? [], canCommit, checkpointPending, qualityReady, signalState);
    if (!checkpointPending && coreReady && !qualityReady) {
      questionPlan = buildQualityQuestionPlan(signalState);
      controlState = {
        postureMode: "Extraction",
        moveType: "MOVE_TARGETED_CLARIFY",
        burdenSignal: "low",
        paceSignal: "narrowing",
        transitionReason: "quality_signal_not_ready",
      };
      questionPlan = sanitizeQuestionPlan(questionPlan);
    } else if (!checkpointPending && canCommit) {
      questionPlan = {
        assistant_message: qualityBoostAvailable
          ? "Great progress. You can generate your draft now, or answer one more easy question to improve it."
          : "Great progress. Your draft is ready to generate.",
        suggestions: qualityBoostAvailable
          ? [
            { id: "readiness:ready_to_commit", label: "Generate my draft plan" },
            { id: "readiness:improve_quality", label: "One more quick improvement question" },
          ]
          : [{ id: "readiness:ready_to_commit", label: "Generate my draft plan" }],
        why_question: "core_and_quality_ready",
      };
      controlState = {
        postureMode: "Alignment Checkpoint",
        moveType: "MOVE_ALIGNMENT_CHECKPOINT",
        burdenSignal: "low",
        paceSignal: "narrowing",
        transitionReason: "ready_for_commit",
      };
      questionPlan = sanitizeQuestionPlan(questionPlan);
    }
    const readiness = buildReadinessState({
      decisions: latestDecisions,
      unresolvedCount: unresolved.length,
      checkpointPending,
      hasArtifactContext: Boolean(artifactContext.row),
      artifactVerified: artifactContext.row ? artifactContext.row.verification_state !== "unverified" : true,
      qualityReady,
      signalState,
    });

    await persistReadinessSnapshot(serviceClient, {
      projectId,
      cycleNo,
      turnId: assistantTurnInsert.row.id,
      readiness,
    });

    await serviceClient.from("audit_events").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      actor_type: "SERVICE",
      actor_id: userId,
      event_type: "brain.next_turn",
      payload: {
        correlation_id: correlationId,
        why_question: questionPlan.why_question,
        selected_option_id: selectedOptionId || null,
        unresolved_count: unresolved.length,
        can_commit: canCommit,
        posture_mode: controlState.postureMode,
        move_type: controlState.moveType,
        artifact_ref: artifactRef || null,
        artifact_input_id: artifactContext.row?.id ?? null,
        ingest_run_id: artifactContext.ingestRunId,
        idempotency_key: artifactContext.idempotencyKey,
        checkpoint_id: activeCheckpoint?.id ?? null,
        checkpoint_status: activeCheckpoint?.status ?? null,
      },
    });

    return json({
      project_id: projectId,
      cycle_no: cycleNo,
      user_turn_id: userTurnInsert.row.id,
      assistant_turn_id: assistantTurnInsert.row.id,
      assistant_message: questionPlan.assistant_message,
      options: questionPlan.suggestions,
      posture_mode: controlState.postureMode,
      move_type: controlState.moveType,
      unresolved,
      can_commit: canCommit,
      commit_blockers: commitBlockers,
      quality_ready: qualityReady,
      quality_boost_available: qualityBoostAvailable,
      quality_hint: qualityHint,
      readiness,
      why_question: questionPlan.why_question,
      checkpoint: activeCheckpoint
        ? {
          id: activeCheckpoint.id,
          type: activeCheckpoint.type,
          status: activeCheckpoint.status,
          prompt: activeCheckpoint.prompt,
          options: activeCheckpoint.options,
          requires_response: activeCheckpoint.status === "pending",
        }
        : null,
      artifact: artifactContext.row
        ? {
          id: artifactContext.row.id,
          artifact_type: artifactContext.row.artifact_type,
          artifact_ref: artifactContext.row.artifact_ref,
          ingest_state: artifactContext.row.ingest_state,
          verification_state: artifactContext.row.verification_state,
          status_message: artifactContext.statusMessage,
          summary_text: artifactContext.row.summary_text,
          provenance_refs: artifactContext.provenanceRefs,
        }
        : null,
      provenance_refs: artifactContext.provenanceRefs,
      trace: {
        correlation_id: correlationId,
        project_id: projectId,
        cycle_no: cycleNo,
        user_turn_id: userTurnInsert.row.id,
        assistant_turn_id: assistantTurnInsert.row.id,
      },
    });
  } catch (error) {
    return fail(500, "UNHANDLED_EXCEPTION", String(error), "server");
  }
});

async function processArtifactContext(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    projectId: string;
    cycleNo: number;
    userTurnId: string;
    artifactRef: string;
    artifactTypeRaw: string;
    selectedOptionId: string;
    noneFitText: string;
    forceRefresh: boolean;
    openAIKey: string;
    brainVersion: string;
    correlationId: string;
  },
): Promise<{ data: ArtifactContext } | { error: Response }> {
  let artifactRow: ArtifactInputRow | null = null;

  if (input.artifactRef) {
    const normalizedRef = input.artifactRef.trim();
    const artifactType = normalizeArtifactType(input.artifactTypeRaw);

    const { data: existing, error: selectError } = await serviceClient
      .from("artifact_inputs")
      .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
      .eq("project_id", input.projectId)
      .eq("cycle_no", input.cycleNo)
      .eq("artifact_type", artifactType)
      .eq("artifact_ref", normalizedRef)
      .maybeSingle();

    if (selectError) return { error: failFromDbError(selectError, "artifact_inputs.select") };

    if (!existing) {
      const { data: inserted, error: insertError } = await serviceClient
        .from("artifact_inputs")
        .insert({
          project_id: input.projectId,
          cycle_no: input.cycleNo,
          artifact_type: artifactType,
          artifact_ref: normalizedRef,
          ingest_state: "pending",
          verification_state: "unverified",
          summary_text: null,
        })
        .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
        .single();
      if (insertError || !inserted) return { error: failFromDbError(insertError, "artifact_inputs.insert") };
      artifactRow = toArtifactInputRow(inserted);
    } else {
      artifactRow = toArtifactInputRow(existing);
    }
  } else {
    const { data: latest, error: latestError } = await serviceClient
      .from("artifact_inputs")
      .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
      .eq("project_id", input.projectId)
      .eq("cycle_no", input.cycleNo)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (latestError) return { error: failFromDbError(latestError, "artifact_inputs.select_latest") };
    artifactRow = latest ? toArtifactInputRow(latest) : null;
  }

  let provenanceRefs: string[] = [];
  let statusMessage: string | null = null;
  let ingestRunId: string | null = null;
  let summaryId: string | null = null;
  let summaryVersion: number | null = null;
  let idempotencyKey: string | null = null;

  if (artifactRow) {
    const requiresIngestion = input.forceRefresh || artifactRow.ingest_state === "pending" || artifactRow.ingest_state === "failed" || !artifactRow.summary_text;

    if (requiresIngestion) {
      const ingestion = await ingestArtifactSync(serviceClient, {
        projectId: input.projectId,
        cycleNo: input.cycleNo,
        artifactInput: artifactRow,
        openAIKey: input.openAIKey,
        brainVersion: input.brainVersion,
        forceRefresh: input.forceRefresh,
        correlationId: input.correlationId,
      });
      if ("error" in ingestion) return { error: ingestion.error };
      artifactRow = ingestion.data.row;
      provenanceRefs = ingestion.data.provenanceRefs;
      statusMessage = ingestion.data.statusMessage;
      ingestRunId = ingestion.data.ingestRunId;
      summaryId = ingestion.data.summaryId;
      summaryVersion = ingestion.data.summaryVersion;
      idempotencyKey = ingestion.data.idempotencyKey;
    }

    if (!statusMessage) {
      statusMessage = buildArtifactStatusMessage(artifactRow);
    }

    if (provenanceRefs.length === 0 || !summaryId || !ingestRunId || summaryVersion === null) {
      const latestSummary = await fetchLatestArtifactSummaryMeta(serviceClient, artifactRow.id);
      if (latestSummary) {
        provenanceRefs = latestSummary.provenanceRefs;
        summaryId = latestSummary.summaryId;
        summaryVersion = latestSummary.summaryVersion;
        if (!ingestRunId) ingestRunId = latestSummary.ingestRunId;
        if (!artifactRow.summary_text && latestSummary.summaryText) {
          artifactRow = { ...artifactRow, summary_text: latestSummary.summaryText };
        }
      }
    }
  }

  return {
    data: {
      row: artifactRow,
      provenanceRefs,
      statusMessage,
      ingestRunId,
      summaryId,
      summaryVersion,
      idempotencyKey,
    },
  };
}

async function resolveOrCreateCheckpoint(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    projectId: string;
    cycleNo: number;
    userTurnId: string;
    artifactContext: ArtifactContext;
    checkpointResponseInput: CheckpointResponseInput | null;
    userText: string;
    brainVersion: string;
  },
): Promise<{ data: { checkpoint: NextTurnCheckpoint | null; artifactContext: ArtifactContext } } | { error: Response }> {
  const artifactRow = input.artifactContext.row;
  if (!artifactRow) {
    return { data: { checkpoint: null, artifactContext: input.artifactContext } };
  }

  if (artifactRow.verification_state !== "unverified") {
    return { data: { checkpoint: null, artifactContext: input.artifactContext } };
  }

  const canonicalUrl = canonicalizeCheckpointUrl(artifactRow.artifact_ref);
  const checkpointKey = await sha256String(JSON.stringify({
    canonical_url: canonicalUrl,
    ingest_run_id: input.artifactContext.ingestRunId ?? "none",
    summary_version: input.artifactContext.summaryVersion ?? 0,
  }));

  const prompt = buildArtifactCheckpointPrompt({
    artifact: artifactRow,
    statusMessage: input.artifactContext.statusMessage,
    hasStoredRefs: input.artifactContext.provenanceRefs.length > 0,
  });
  const options: Suggestion[] = [
    { id: "checkpoint:confirm", label: "Yes, correct" },
    { id: "checkpoint:reject", label: "No, incorrect" },
    { id: "checkpoint:partial", label: "Partially / refine" },
  ];

  const { data: existing, error: selectError } = await serviceClient
    .from("interview_checkpoints")
    .select("id,checkpoint_type,checkpoint_key,status,payload")
    .eq("project_id", input.projectId)
    .eq("cycle_no", input.cycleNo)
    .eq("checkpoint_type", "artifact_verification")
    .eq("checkpoint_key", checkpointKey)
    .maybeSingle();
  if (selectError) return { error: failFromDbError(selectError, "interview_checkpoints.select") };

  let checkpointRow: CheckpointRow;
  if (!existing) {
    const summaryHash = artifactRow.summary_text ? await sha256String(artifactRow.summary_text) : null;
    const payload = {
      prompt,
      options,
      artifact_input_id: artifactRow.id,
      artifact_type: artifactRow.artifact_type,
      artifact_ref: artifactRow.artifact_ref,
      canonical_url: canonicalUrl,
      ingest_run_id: input.artifactContext.ingestRunId,
      summary_id: input.artifactContext.summaryId,
      summary_version: input.artifactContext.summaryVersion,
      summary_hash: summaryHash,
      provenance_refs: input.artifactContext.provenanceRefs,
      brain_version: input.brainVersion,
    };
    const { data: inserted, error: insertError } = await serviceClient
      .from("interview_checkpoints")
      .insert({
        project_id: input.projectId,
        cycle_no: input.cycleNo,
        checkpoint_type: "artifact_verification",
        checkpoint_key: checkpointKey,
        status: "pending",
        created_turn_id: input.userTurnId,
        payload,
      })
      .select("id,checkpoint_type,checkpoint_key,status,payload")
      .single();
    if (insertError || !inserted) return { error: failFromDbError(insertError, "interview_checkpoints.insert") };
    checkpointRow = toCheckpointRow(inserted);
  } else {
    checkpointRow = toCheckpointRow(existing);
  }

  const implicitAction = inferCheckpointActionFromText(input.userText);
  const resolvedInput = input.checkpointResponseInput
    ? input.checkpointResponseInput
    : (implicitAction ? { action: implicitAction } as CheckpointResponseInput : null);
  const checkpointIdMatches = !resolvedInput?.checkpoint_id || resolvedInput.checkpoint_id === checkpointRow.id;
  const shouldResolve = checkpointRow.status === "pending" && resolvedInput && checkpointIdMatches;

  if (shouldResolve) {
    const action = resolvedInput.action;
    const resolvedStatus: CheckpointStatus = action === "confirm"
      ? "confirmed"
      : (action === "skip" ? "skipped" : "rejected");
    const optionalText = (resolvedInput.optional_text ?? "").trim();

    const mergedPayload = {
      ...(checkpointRow.payload ?? {}),
      resolved_action: action,
      resolved_text: optionalText || null,
      resolved_turn_id: input.userTurnId,
    };

    const resolvedAt = new Date().toISOString();
    const { data: updatedCheckpoint, error: updateCheckpointError } = await serviceClient
      .from("interview_checkpoints")
      .update({
        status: resolvedStatus,
        resolved_turn_id: input.userTurnId,
        resolved_at: resolvedAt,
        updated_at: resolvedAt,
        payload: mergedPayload,
      })
      .eq("id", checkpointRow.id)
      .select("id,checkpoint_type,checkpoint_key,status,payload")
      .single();
    if (updateCheckpointError || !updatedCheckpoint) {
      return { error: failFromDbError(updateCheckpointError, "interview_checkpoints.update") };
    }

    const verificationState = action === "confirm" ? "user_confirmed" : "user_corrected";
    const artifactSummaryText = optionalText.length > 0 && action !== "confirm"
      ? optionalText
      : artifactRow.summary_text;
    const { data: updatedArtifact, error: updateArtifactError } = await serviceClient
      .from("artifact_inputs")
      .update({
        verification_state: verificationState,
        summary_text: artifactSummaryText,
      })
      .eq("id", artifactRow.id)
      .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
      .single();
    if (updateArtifactError || !updatedArtifact) {
      return { error: failFromDbError(updateArtifactError, "artifact_inputs.update_after_checkpoint") };
    }

    return {
      data: {
        checkpoint: null,
        artifactContext: {
          ...input.artifactContext,
          row: toArtifactInputRow(updatedArtifact),
          statusMessage: buildArtifactStatusMessage(toArtifactInputRow(updatedArtifact)),
        },
      },
    };
  }

  const checkpointPayload = checkpointRow.payload ?? {};
  const checkpointPrompt = String(checkpointPayload.prompt ?? prompt);
  const checkpointOptions = normalizeCheckpointOptions(checkpointPayload.options, options);

  return {
    data: {
      checkpoint: {
        id: checkpointRow.id,
        type: checkpointRow.checkpoint_type,
        status: checkpointRow.status,
        prompt: checkpointPrompt,
        options: checkpointOptions,
        requires_response: checkpointRow.status === "pending",
      },
      artifactContext: input.artifactContext,
    },
  };
}

async function ingestArtifactSync(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    projectId: string;
    cycleNo: number;
    artifactInput: ArtifactInputRow;
    openAIKey: string;
    brainVersion: string;
    forceRefresh: boolean;
    correlationId: string;
  },
): Promise<
  | { data: { row: ArtifactInputRow; provenanceRefs: string[]; statusMessage: string; ingestRunId: string; summaryId: string | null; summaryVersion: number | null; idempotencyKey: string } }
  | { error: Response }
> {
  const canonicalRef = canonicalizeUrl(input.artifactInput.artifact_ref);
  if (!canonicalRef.ok) {
    const { data: failedRow, error: updateError } = await serviceClient
      .from("artifact_inputs")
      .update({
        ingest_state: "failed",
        summary_text: canonicalRef.message,
      })
      .eq("id", input.artifactInput.id)
      .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
      .single();
    if (updateError || !failedRow) return { error: failFromDbError(updateError, "artifact_inputs.update_failed") };
    return {
      data: {
        row: toArtifactInputRow(failedRow),
        provenanceRefs: [],
        statusMessage: canonicalRef.message,
        ingestRunId: "",
        summaryId: null,
        summaryVersion: null,
        idempotencyKey: "",
      },
    };
  }

  const idempotencyPayload = JSON.stringify({
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    canonical_url: canonicalRef.url,
    ingestion_limits_version: INGESTION_LIMITS_VERSION,
    brain_version: input.brainVersion,
  });
  const idempotencyKey = await sha256String(idempotencyPayload);

  if (!input.forceRefresh) {
    const { data: priorRun } = await serviceClient
      .from("artifact_ingest_runs")
      .select("id,status,error_message")
      .eq("project_id", input.projectId)
      .eq("cycle_no", input.cycleNo)
      .eq("artifact_input_id", input.artifactInput.id)
      .eq("idempotency_key", idempotencyKey)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (priorRun) {
      const summaryResult = await fetchLatestSummaryForRun(serviceClient, String((priorRun as Record<string, unknown>).id));
      const status = String((priorRun as Record<string, unknown>).status ?? "failed") as ArtifactInputRow["ingest_state"];
      const summaryText = summaryResult?.summary_text ?? String((priorRun as Record<string, unknown>).error_message ?? "Artifact ingestion reused prior result.");

      const { data: updated, error: updateError } = await serviceClient
        .from("artifact_inputs")
        .update({ ingest_state: status, summary_text: summaryText })
        .eq("id", input.artifactInput.id)
        .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
        .single();
      if (updateError || !updated) return { error: failFromDbError(updateError, "artifact_inputs.update_reused") };

      return {
        data: {
          row: toArtifactInputRow(updated),
          provenanceRefs: summaryResult?.provenance_refs ?? [],
          statusMessage: buildArtifactStatusMessage(toArtifactInputRow(updated)),
          ingestRunId: String((priorRun as Record<string, unknown>).id),
          summaryId: summaryResult?.summary_id ?? null,
          summaryVersion: summaryResult?.summary_version ?? null,
          idempotencyKey,
        },
      };
    }
  }

  const fetchOutcome = await fetchAndExtractWebsite(canonicalRef.url);
  const now = new Date().toISOString();
  const sourceHash = fetchOutcome.extractedText
    ? await sha256String(fetchOutcome.extractedText)
    : null;

  const { data: ingestRun, error: ingestRunError } = await serviceClient
    .from("artifact_ingest_runs")
    .insert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      artifact_input_id: input.artifactInput.id,
      idempotency_key: idempotencyKey,
      canonical_url: fetchOutcome.canonicalUrl,
      ingestion_limits_version: INGESTION_LIMITS_VERSION,
      brain_version: input.brainVersion,
      status: fetchOutcome.status,
      http_status: fetchOutcome.httpStatus,
      error_code: fetchOutcome.errorCode,
      error_message: fetchOutcome.errorMessage,
      bytes_total: fetchOutcome.bytesRead,
      pages_fetched: fetchOutcome.extractedText ? 1 : 0,
      source_hash: sourceHash,
      started_at: now,
      ended_at: now,
    })
    .select("id")
    .single();

  if (ingestRunError || !ingestRun) return { error: failFromDbError(ingestRunError, "artifact_ingest_runs.insert") };
  const ingestRunId = String((ingestRun as Record<string, unknown>).id);

  const provenanceRefs: string[] = [];
  let summaryId: string | null = null;
  let summaryVersion: number | null = null;
  let summaryText = fetchOutcome.errorMessage ?? "";

  if (fetchOutcome.extractedText.trim().length >= MIN_EXTRACT_CHARS) {
    const { data: pageRow, error: pageError } = await serviceClient
      .from("artifact_pages")
      .insert({
        project_id: input.projectId,
        cycle_no: input.cycleNo,
        artifact_input_id: input.artifactInput.id,
        ingest_run_id: ingestRunId,
        url: fetchOutcome.canonicalUrl,
        canonical_url: fetchOutcome.canonicalUrl,
        depth: 0,
        fetch_status: fetchOutcome.status === "failed" ? "failed" : "fetched",
        content_type: fetchOutcome.contentType,
        http_status: fetchOutcome.httpStatus,
        content_hash: sourceHash,
        raw_text: fetchOutcome.extractedText,
        text_char_count: fetchOutcome.extractedText.length,
      })
      .select("id")
      .single();

    if (pageError || !pageRow) return { error: failFromDbError(pageError, "artifact_pages.insert") };
    const pageId = String((pageRow as Record<string, unknown>).id);
    provenanceRefs.push(`artifact_page:${pageId}`);

    const { data: storedPage, error: storedPageError } = await serviceClient
      .from("artifact_pages")
      .select("raw_text")
      .eq("id", pageId)
      .single();
    if (storedPageError || !storedPage) return { error: failFromDbError(storedPageError, "artifact_pages.select_stored") };

    const storedExtract = String((storedPage as Record<string, unknown>).raw_text ?? "");
    const summaryResult = await summarizeStoredExtract({
      openAIKey: input.openAIKey,
      canonicalUrl: fetchOutcome.canonicalUrl,
      extractedText: storedExtract,
      wasPartial: fetchOutcome.status === "partial",
    });
    summaryText = summaryResult.summary;

    const nextVersionNo = await nextArtifactSummaryVersion(serviceClient, {
      projectId: input.projectId,
      cycleNo: input.cycleNo,
      artifactInputId: input.artifactInput.id,
    });

    const { data: summaryRow, error: summaryError } = await serviceClient
      .from("artifact_summaries")
      .insert({
        project_id: input.projectId,
        cycle_no: input.cycleNo,
        artifact_input_id: input.artifactInput.id,
        ingest_run_id: ingestRunId,
        version_no: nextVersionNo,
        summary_text: summaryText,
        summary_confidence: summaryResult.confidence,
        source_page_ids: [pageId],
      })
      .select("id")
      .single();

    if (summaryError || !summaryRow) return { error: failFromDbError(summaryError, "artifact_summaries.insert") };
    summaryId = String((summaryRow as Record<string, unknown>).id);
    summaryVersion = nextVersionNo;
    provenanceRefs.push(`artifact_summary:${summaryId}`);
  }

  const { data: updatedInput, error: updateInputError } = await serviceClient
    .from("artifact_inputs")
    .update({
      ingest_state: fetchOutcome.status,
      summary_text: summaryText || buildFallbackIngestSummary(fetchOutcome),
    })
    .eq("id", input.artifactInput.id)
    .select("id,artifact_type,artifact_ref,ingest_state,verification_state,summary_text")
    .single();
  if (updateInputError || !updatedInput) return { error: failFromDbError(updateInputError, "artifact_inputs.update_ingest") };

  const updatedRow = toArtifactInputRow(updatedInput);
  const statusMessage = buildArtifactStatusMessage(updatedRow);

  await serviceClient.from("audit_events").insert({
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    actor_type: "SERVICE",
    event_type: "artifact.ingested",
    payload: {
      correlation_id: input.correlationId,
      artifact_input_id: updatedRow.id,
      ingest_run_id: ingestRunId,
      idempotency_key: idempotencyKey,
      ingest_state: updatedRow.ingest_state,
      summary_id: summaryId,
      provenance_refs: provenanceRefs,
    },
  });

  return {
    data: {
      row: updatedRow,
      provenanceRefs,
      statusMessage,
      ingestRunId,
      summaryId,
      summaryVersion,
      idempotencyKey,
    },
  };
}

async function fetchLatestSummaryForRun(
  serviceClient: ReturnType<typeof createClient>,
  ingestRunId: string,
): Promise<{ summary_id: string | null; summary_text: string | null; summary_version: number | null; provenance_refs: string[] } | null> {
  const { data: summary } = await serviceClient
    .from("artifact_summaries")
    .select("id,summary_text,version_no,source_page_ids")
    .eq("ingest_run_id", ingestRunId)
    .order("version_no", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!summary) return null;

  const summaryId = String((summary as Record<string, unknown>).id);
  const summaryText = String((summary as Record<string, unknown>).summary_text ?? "");
  const pageIds = Array.isArray((summary as Record<string, unknown>).source_page_ids)
    ? ((summary as Record<string, unknown>).source_page_ids as unknown[]).map((value) => String(value))
    : [];
  const refs = pageIds.map((id) => `artifact_page:${id}`);
  refs.push(`artifact_summary:${summaryId}`);

  return {
    summary_id: summaryId,
    summary_text: summaryText,
    summary_version: Number((summary as Record<string, unknown>).version_no ?? 0) || null,
    provenance_refs: refs,
  };
}

async function fetchLatestArtifactSummaryMeta(
  serviceClient: ReturnType<typeof createClient>,
  artifactInputId: string,
): Promise<LatestSummaryMeta | null> {
  const { data: latestSummary } = await serviceClient
    .from("artifact_summaries")
    .select("id,summary_text,version_no,ingest_run_id,source_page_ids")
    .eq("artifact_input_id", artifactInputId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!latestSummary) return null;

  const summaryId = String((latestSummary as Record<string, unknown>).id);
  const summaryText = String((latestSummary as Record<string, unknown>).summary_text ?? "");
  const summaryVersion = Number((latestSummary as Record<string, unknown>).version_no ?? 0) || 1;
  const ingestRunIdRaw = (latestSummary as Record<string, unknown>).ingest_run_id;
  const ingestRunId = ingestRunIdRaw ? String(ingestRunIdRaw) : null;
  const pageIds = Array.isArray((latestSummary as Record<string, unknown>).source_page_ids)
    ? ((latestSummary as Record<string, unknown>).source_page_ids as unknown[]).map((value) => String(value))
    : [];

  const provenanceRefs = pageIds.map((id) => `artifact_page:${id}`);
  provenanceRefs.push(`artifact_summary:${summaryId}`);
  return {
    summaryId,
    summaryText,
    summaryVersion,
    ingestRunId,
    provenanceRefs,
  };
}

async function nextArtifactSummaryVersion(
  serviceClient: ReturnType<typeof createClient>,
  input: { projectId: string; cycleNo: number; artifactInputId: string },
): Promise<number> {
  const { data } = await serviceClient
    .from("artifact_summaries")
    .select("version_no")
    .eq("project_id", input.projectId)
    .eq("cycle_no", input.cycleNo)
    .eq("artifact_input_id", input.artifactInputId)
    .order("version_no", { ascending: false })
    .limit(1)
    .maybeSingle();

  return Number((data as Record<string, unknown> | null)?.version_no ?? 0) + 1;
}

async function summarizeStoredExtract(input: {
  openAIKey: string;
  canonicalUrl: string;
  extractedText: string;
  wasPartial: boolean;
}): Promise<{ summary: string; confidence: number }> {
  const fallback = deterministicSummary(input.canonicalUrl, input.extractedText, input.wasPartial);
  if (!input.openAIKey) return fallback;

  try {
    const clipped = input.extractedText.slice(0, 6000);
    const prompt = [
      "Summarize this extracted website text for interview grounding.",
      "Rules:",
      "- Use only provided extracted text.",
      "- Do not claim unseen details.",
      "- 2-3 short sentences.",
      "- Output JSON with keys: summary, confidence.",
      `URL: ${input.canonicalUrl}`,
      `Extracted text: ${clipped}`,
    ].join("\n");

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${input.openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.1,
        max_tokens: 180,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: "You are a careful summarizer for provenance-constrained intake systems." },
          { role: "user", content: prompt },
        ],
      }),
    });

    if (!response.ok) return fallback;
    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (!content) return fallback;

    const parsed = JSON.parse(content) as { summary?: string; confidence?: number };
    const summary = String(parsed.summary ?? "").trim();
    const confidence = Number(parsed.confidence ?? (input.wasPartial ? 0.55 : 0.75));

    if (!summary) return fallback;
    return {
      summary,
      confidence: Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : fallback.confidence,
    };
  } catch {
    return fallback;
  }
}

function deterministicSummary(canonicalUrl: string, extractedText: string, wasPartial: boolean): { summary: string; confidence: number } {
  const sentences = extractedText
    .replace(/\s+/g, " ")
    .split(/(?<=[.!?])\s+/)
    .map((part) => part.trim())
    .filter(Boolean)
    .slice(0, 3)
    .join(" ");

  const summary = sentences.length > 0
    ? `Based on extracted website content from ${canonicalUrl}, this appears to describe: ${sentences}`
    : `I could not extract enough readable content from ${canonicalUrl} to summarize reliably.`;

  return {
    summary,
    confidence: wasPartial ? 0.55 : 0.75,
  };
}

async function fetchAndExtractWebsite(inputUrl: string): Promise<FetchOutcome> {
  const safe = canonicalizeUrl(inputUrl);
  if (!safe.ok) {
    return {
      status: "failed",
      canonicalUrl: inputUrl,
      httpStatus: null,
      contentType: null,
      extractedText: "",
      bytesRead: 0,
      truncated: false,
      errorCode: "INVALID_URL",
      errorMessage: safe.message,
    };
  }

  let current = safe.url;
  let redirects = 0;
  let lastResponse: Response | null = null;

  while (redirects <= MAX_REDIRECTS) {
    const currentUrl = new URL(current);
    if (isBlockedHost(currentUrl.hostname)) {
      return {
        status: "failed",
        canonicalUrl: current,
        httpStatus: null,
        contentType: null,
        extractedText: "",
        bytesRead: 0,
        truncated: false,
        errorCode: "HOST_BLOCKED",
        errorMessage: "This URL points to a blocked or private network host.",
      };
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    try {
      lastResponse = await fetch(current, {
        method: "GET",
        redirect: "manual",
        signal: controller.signal,
        headers: {
          "User-Agent": "ShipFirstBot/1.0 (+https://shipfirst.app)",
          Accept: "text/html,text/plain;q=0.9,*/*;q=0.1",
        },
      });
    } catch (error) {
      clearTimeout(timeout);
      const isAbort = String(error).toLowerCase().includes("abort");
      return {
        status: "failed",
        canonicalUrl: current,
        httpStatus: null,
        contentType: null,
        extractedText: "",
        bytesRead: 0,
        truncated: false,
        errorCode: isAbort ? "TIMEOUT" : "FETCH_ERROR",
        errorMessage: isAbort ? "Website fetch timed out." : `Website fetch failed: ${String(error)}`,
      };
    } finally {
      clearTimeout(timeout);
    }

    if (!lastResponse) break;

    if (lastResponse.status >= 300 && lastResponse.status < 400) {
      const location = lastResponse.headers.get("location");
      if (!location) {
        return {
          status: "failed",
          canonicalUrl: current,
          httpStatus: lastResponse.status,
          contentType: null,
          extractedText: "",
          bytesRead: 0,
          truncated: false,
          errorCode: "REDIRECT_MISSING_LOCATION",
          errorMessage: "Redirect response did not include a location header.",
        };
      }

      redirects += 1;
      if (redirects > MAX_REDIRECTS) {
        return {
          status: "failed",
          canonicalUrl: current,
          httpStatus: lastResponse.status,
          contentType: null,
          extractedText: "",
          bytesRead: 0,
          truncated: false,
          errorCode: "REDIRECT_LIMIT_EXCEEDED",
          errorMessage: "Too many redirects while fetching website content.",
        };
      }

      const next = new URL(location, current).toString();
      const nextSafe = canonicalizeUrl(next);
      if (!nextSafe.ok) {
        return {
          status: "failed",
          canonicalUrl: current,
          httpStatus: lastResponse.status,
          contentType: null,
          extractedText: "",
          bytesRead: 0,
          truncated: false,
          errorCode: "REDIRECT_INVALID_URL",
          errorMessage: nextSafe.message,
        };
      }
      current = nextSafe.url;
      continue;
    }

    break;
  }

  if (!lastResponse) {
    return {
      status: "failed",
      canonicalUrl: current,
      httpStatus: null,
      contentType: null,
      extractedText: "",
      bytesRead: 0,
      truncated: false,
      errorCode: "NO_RESPONSE",
      errorMessage: "No response received while fetching website.",
    };
  }

  const contentType = (lastResponse.headers.get("content-type") ?? "").toLowerCase();
  if (!(contentType.includes("text/html") || contentType.includes("text/plain"))) {
    return {
      status: "failed",
      canonicalUrl: current,
      httpStatus: lastResponse.status,
      contentType,
      extractedText: "",
      bytesRead: 0,
      truncated: false,
      errorCode: "UNSUPPORTED_CONTENT_TYPE",
      errorMessage: "Website content type is not supported for ingestion.",
    };
  }

  if (!lastResponse.ok) {
    return {
      status: "failed",
      canonicalUrl: current,
      httpStatus: lastResponse.status,
      contentType,
      extractedText: "",
      bytesRead: 0,
      truncated: false,
      errorCode: "HTTP_STATUS_NOT_OK",
      errorMessage: `Website returned HTTP ${lastResponse.status}.`,
    };
  }

  const limited = await readResponseTextLimited(lastResponse, MAX_FETCH_BYTES);
  const extracted = contentType.includes("text/html")
    ? normalizeHtmlToText(limited.text)
    : normalizePlainText(limited.text);

  if (extracted.length < MIN_EXTRACT_CHARS) {
    return {
      status: "failed",
      canonicalUrl: current,
      httpStatus: lastResponse.status,
      contentType,
      extractedText: extracted,
      bytesRead: limited.bytesRead,
      truncated: limited.truncated,
      errorCode: "EXTRACT_TOO_SMALL",
      errorMessage: "Extracted text was too limited to trust as grounding context.",
    };
  }

  return {
    status: limited.truncated ? "partial" : "complete",
    canonicalUrl: current,
    httpStatus: lastResponse.status,
    contentType,
    extractedText: extracted,
    bytesRead: limited.bytesRead,
    truncated: limited.truncated,
    errorCode: null,
    errorMessage: null,
  };
}

async function readResponseTextLimited(response: Response, maxBytes: number): Promise<{ text: string; bytesRead: number; truncated: boolean }> {
  if (!response.body) {
    const text = await response.text();
    const bytes = new TextEncoder().encode(text);
    return {
      text: new TextDecoder().decode(bytes.slice(0, maxBytes)),
      bytesRead: Math.min(bytes.length, maxBytes),
      truncated: bytes.length > maxBytes,
    };
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytesRead = 0;
  let truncated = false;

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    if (!value) continue;

    if (bytesRead + value.length <= maxBytes) {
      chunks.push(value);
      bytesRead += value.length;
      continue;
    }

    const remaining = Math.max(0, maxBytes - bytesRead);
    if (remaining > 0) {
      chunks.push(value.slice(0, remaining));
      bytesRead += remaining;
    }
    truncated = true;
    try {
      await reader.cancel();
    } catch {
      // Ignore cancel errors.
    }
    break;
  }

  const total = new Uint8Array(bytesRead);
  let offset = 0;
  for (const chunk of chunks) {
    total.set(chunk, offset);
    offset += chunk.length;
  }

  return {
    text: new TextDecoder().decode(total),
    bytesRead,
    truncated,
  };
}

function normalizeHtmlToText(html: string): string {
  const withoutScripts = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<!--([\s\S]*?)-->/g, " ");

  const withLineBreaks = withoutScripts
    .replace(/<(\/p|\/div|\/section|\/article|\/li|br|\/h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ");

  return decodeHtmlEntities(withLineBreaks)
    .replace(/\r/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function normalizePlainText(text: string): string {
  return text
    .replace(/\r/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function decodeHtmlEntities(input: string): string {
  return input
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

function canonicalizeUrl(raw: string): { ok: true; url: string } | { ok: false; message: string } {
  try {
    const parsed = new URL(raw.trim());
    if (parsed.protocol !== "https:") {
      return { ok: false, message: "Only https:// URLs are allowed for website ingestion." };
    }
    if (isBlockedHost(parsed.hostname)) {
      return { ok: false, message: "This URL points to a blocked or private network host." };
    }
    parsed.hash = "";
    if ((parsed.pathname === "/" || parsed.pathname === "") && !parsed.search) {
      parsed.pathname = "/";
    }
    return { ok: true, url: parsed.toString() };
  } catch {
    return { ok: false, message: "The provided URL is invalid." };
  }
}

function isBlockedHost(hostnameRaw: string): boolean {
  const hostname = hostnameRaw.toLowerCase();
  if (!hostname) return true;
  if (hostname === "localhost" || hostname.endsWith(".local")) return true;
  if (hostname === "::1") return true;
  if (/^127\./.test(hostname)) return true;
  if (/^10\./.test(hostname)) return true;
  if (/^192\.168\./.test(hostname)) return true;
  if (/^169\.254\./.test(hostname)) return true;
  const match172 = hostname.match(/^172\.(\d{1,3})\./);
  if (match172) {
    const segment = Number(match172[1]);
    if (segment >= 16 && segment <= 31) return true;
  }
  return false;
}

function buildFallbackIngestSummary(fetchOutcome: FetchOutcome): string {
  if (fetchOutcome.status === "failed") {
    return fetchOutcome.errorMessage ?? "Website ingestion failed before readable content could be extracted.";
  }
  if (fetchOutcome.status === "partial") {
    return "I could only extract part of the website content. Please confirm or correct what matters most.";
  }
  return "Website content was extracted and is ready for verification.";
}

function buildArtifactStatusMessage(row: ArtifactInputRow): string {
  if (row.ingest_state === "failed") {
    return "Website ingestion failed or was incomplete; please paste key text or narrow to a specific page.";
  }
  if (row.ingest_state === "partial") {
    return "Website ingestion is partial; please verify or correct before we narrow product decisions.";
  }
  if (row.ingest_state === "complete" && row.verification_state === "unverified") {
    return "Website content was extracted; please verify my understanding before we continue.";
  }
  if (row.verification_state === "user_confirmed") {
    return "Website understanding confirmed by user.";
  }
  if (row.verification_state === "user_corrected") {
    return "Website understanding corrected by user and needs to be respected as latest context.";
  }
  return "Artifact context recorded.";
}

function toArtifactInputRow(row: Record<string, unknown>): ArtifactInputRow {
  return {
    id: String(row.id),
    artifact_type: String(row.artifact_type),
    artifact_ref: String(row.artifact_ref),
    ingest_state: String(row.ingest_state) as ArtifactInputRow["ingest_state"],
    verification_state: String(row.verification_state) as ArtifactInputRow["verification_state"],
    summary_text: row.summary_text ? String(row.summary_text) : null,
  };
}

function extractFirstUrl(input: string): string | null {
  if (!input) return null;
  const match = input.match(/https:\/\/[^\s)\]]+/i);
  return match ? match[0].trim() : null;
}

async function insertTurn(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    projectId: string;
    cycleNo: number;
    turnIndex: number;
    actorType: "USER" | "SYSTEM";
    rawText: string;
  },
): Promise<{ row: { id: string } } | { error: Response }> {
  const basePayload: Record<string, unknown> = {
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    turn_index: input.turnIndex,
    actor_type: input.actorType,
    raw_text: input.rawText,
  };

  let { data, error } = await serviceClient
    .from("intake_turns")
    .insert(basePayload)
    .select("id")
    .single();

  if (error && String(error.code) === "23502" && String(error.message).toLowerCase().includes("column \"actor\"")) {
    const legacyPayload = { ...basePayload, actor: input.actorType };
    ({ data, error } = await serviceClient.from("intake_turns").insert(legacyPayload).select("id").single());
  }

  if (error || !data) {
    return { error: failFromDbError(error, "intake_turns.insert") };
  }

  return { row: { id: String((data as Record<string, unknown>).id) } };
}

async function upsertMeaningMarkers(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    projectId: string;
    cycleNo: number;
    userTurnId: string;
    userText: string;
    selectedOptionId: string;
    noneFitText: string;
    priorDecisions: DecisionItem[];
    artifactVerificationPending: boolean;
  },
) {
  const evidence = [`turn:${input.userTurnId}`];

  if (!isArtifactVerificationSelection(input.selectedOptionId) && input.userText.trim().length > 0) {
    await serviceClient.from("decision_items").upsert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      decision_key: "latest_user_intent",
      claim: input.userText,
      status: "USER_SAID",
      evidence_refs: evidence,
      lock_state: "open",
      confirmed_by_turn_id: input.userTurnId,
      hypothesis_rationale: null,
    }, { onConflict: "project_id,cycle_no,decision_key" });
  }

  const businessDecisionIsLocked = hasExplicitlyConfirmedBusinessType(input.priorDecisions);
  const explicitBusinessTypeSelection = input.selectedOptionId.startsWith("business_type:");

  if (explicitBusinessTypeSelection) {
    const selectedType = input.selectedOptionId.replace("business_type:", "").replace(/_/g, " ");
    await serviceClient.from("decision_items").upsert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      decision_key: "business_type",
      claim: `Business type is ${selectedType}.`,
      status: "USER_SAID",
      evidence_refs: evidence,
      lock_state: "locked",
      locked_at: new Date().toISOString(),
      confirmed_by_turn_id: input.userTurnId,
      hypothesis_rationale: null,
    }, { onConflict: "project_id,cycle_no,decision_key" });
    return;
  }

  const structuredSelection = normalizeStructuredSelection(input.selectedOptionId, input.noneFitText);
  if (structuredSelection) {
    await serviceClient.from("decision_items").upsert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      decision_key: structuredSelection.decisionKey,
      claim: structuredSelection.claim,
      status: "USER_SAID",
      evidence_refs: evidence,
      lock_state: "locked",
      locked_at: new Date().toISOString(),
      confirmed_by_turn_id: input.userTurnId,
      hypothesis_rationale: null,
    }, { onConflict: "project_id,cycle_no,decision_key" });
    return;
  }

  const priorByKey = latestDecisionByKey(input.priorDecisions);
  const coreDecisionsLocked = isDecisionConfirmed(priorByKey["business_type"])
    && isDecisionConfirmed(priorByKey["primary_outcome"])
    && isDecisionConfirmed(priorByKey["launch_capabilities"])
    && isDecisionConfirmed(priorByKey["monetization_path"]);

  if (
    coreDecisionsLocked
    && !input.artifactVerificationPending
    && !isArtifactVerificationSelection(input.selectedOptionId)
    && input.userText.trim().length >= 16
  ) {
    await serviceClient.from("decision_items").upsert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      decision_key: "quality_signal",
      claim: `Quality detail: ${input.userText.trim()}`,
      status: "USER_SAID",
      evidence_refs: evidence,
      lock_state: "locked",
      locked_at: new Date().toISOString(),
      confirmed_by_turn_id: input.userTurnId,
      hypothesis_rationale: null,
    }, { onConflict: "project_id,cycle_no,decision_key" });
    return;
  }

  if (businessDecisionIsLocked || input.artifactVerificationPending) return;

  const inferredBusinessType = inferBusinessTypeFromText(input.userText);
  if (inferredBusinessType) {
    await serviceClient.from("decision_items").upsert({
      project_id: input.projectId,
      cycle_no: input.cycleNo,
      decision_key: "business_type",
      claim: `Possible business type: ${inferredBusinessType}.`,
      status: "ASSUMED",
      evidence_refs: evidence,
      lock_state: "open",
      confirmed_by_turn_id: null,
      hypothesis_rationale: "Inferred from user wording; requires explicit confirmation.",
    }, { onConflict: "project_id,cycle_no,decision_key" });
    return;
  }

  await serviceClient.from("decision_items").upsert({
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    decision_key: "business_type",
    claim: "Business type is still unknown.",
    status: "UNKNOWN",
    evidence_refs: evidence,
    lock_state: "open",
    confirmed_by_turn_id: null,
    hypothesis_rationale: "No explicit business type confirmation yet.",
  }, { onConflict: "project_id,cycle_no,decision_key" });
}

async function buildNextQuestionPlan(input: {
  recentTurns: IntakeTurn[];
  decisions: DecisionItem[];
  latestUserText: string;
  selectedOptionId: string;
}): Promise<NextQuestionPlan> {
  const plan = deterministicQuestionPlan(input.latestUserText, input.selectedOptionId, input.decisions);
  return plan;
}

function buildArtifactVerificationPlan(artifact: ArtifactInputRow, statusMessage: string | null, hasStoredRefs: boolean): NextQuestionPlan {
  const prefix = statusMessage ? `${statusMessage} ` : "";
  const summary = artifact.summary_text && artifact.summary_text.trim().length > 0
    ? artifact.summary_text.trim()
    : "I do not yet have enough extracted site content to summarize reliably.";
  const provenanceNote = hasStoredRefs
    ? "(based on stored extracted website content)"
    : "(I still need usable extracted website content)";

  return {
    assistant_message: `${prefix}${provenanceNote} Did I understand your site correctly: ${summary}`,
    suggestions: [
      { id: "artifact_verify:right", label: "Yes, that is right" },
      { id: "artifact_verify:mostly", label: "Mostly right, needs correction" },
      { id: "artifact_verify:wrong", label: "No, that is not right" },
      { id: "artifact_verify:proceed_uncertain", label: "Proceed with uncertainty" },
    ],
    why_question: "Artifact context is present; comprehension verification must happen before feature narrowing.",
  };
}

function deterministicQuestionPlan(latestUserText: string, selectedOptionId: string, decisions: DecisionItem[]): NextQuestionPlan {
  const lower = latestUserText.trim().toLowerCase();
  const byKey = latestDecisionByKey(decisions);

  if (!isDecisionConfirmed(byKey["business_type"])) {
    return {
      assistant_message: "What kind of app are you building first?",
      suggestions: [
        { id: "business_type:service", label: "Service bookings" },
        { id: "business_type:selling", label: "Selling products or packages" },
        { id: "business_type:content", label: "Content or community" },
        { id: "business_type:internal_tool", label: "Internal business tool" },
        { id: "none_fit", label: "None fit, I’ll describe it" },
      ],
      why_question: "business_type_missing",
    };
  }

  if (!isDecisionConfirmed(byKey["primary_outcome"])) {
    return {
      assistant_message: "What should customers do first in your app?",
      suggestions: [
        { id: "outcome:book", label: "Book a service" },
        { id: "outcome:buy", label: "Buy and pay" },
        { id: "outcome:browse", label: "Browse content or offers" },
        { id: "outcome:request", label: "Send a request" },
        { id: "none_fit", label: "None fit, I’ll describe it" },
      ],
      why_question: "primary_outcome_missing",
    };
  }

  if (!isDecisionConfirmed(byKey["launch_capabilities"])) {
    return {
      assistant_message: "Choose one or two capabilities for version one.",
      suggestions: [
        { id: "capability:online_scheduling", label: "Booking and calendar" },
        { id: "capability:payment_processing", label: "Online payments" },
        { id: "capability:client_reminders", label: "Client reminders" },
        { id: "capability:simple_gallery", label: "Portfolio or gallery" },
        { id: "none_fit", label: "None fit, I’ll describe it" },
      ],
      why_question: "launch_capabilities_missing",
    };
  }

  if (!isDecisionConfirmed(byKey["monetization_path"])) {
    return {
      assistant_message: "How should version one handle payments?",
      suggestions: [
        { id: "monetization:required", label: "Take payments in app now" },
        { id: "monetization:later", label: "Collect requests first, payments later" },
        { id: "monetization:none", label: "No payments needed in version one" },
        { id: "none_fit", label: "None fit, I’ll describe it" },
      ],
      why_question: "monetization_missing",
    };
  }

  if (selectedOptionId === "readiness:improve_quality") {
    return {
      assistant_message: "Great. One quick thing: what should feel uniquely yours in this first version?",
      suggestions: [
        { id: "quality:brand_feel", label: "Brand look and tone" },
        { id: "quality:customer_journey", label: "Customer flow and trust" },
        { id: "quality:operations", label: "How you run it day to day" },
        { id: "none_fit", label: "None fit, I’ll describe it" },
      ],
      why_question: "quality_boost_refinement",
    };
  }

  if (hasUserSignaledScopeComplete(lower)) {
    return {
      assistant_message: "Perfect. We have enough to prepare your draft packet. Want to review blockers or commit now?",
      suggestions: [
        { id: "readiness:review_blockers", label: "Review blockers first" },
        { id: "readiness:ready_to_commit", label: "Ready to commit draft" },
      ],
      why_question: "user_signaled_scope_complete",
    };
  }

  if (selectedOptionId.startsWith("capability:") || selectedOptionId.startsWith("monetization:")) {
    return {
      assistant_message: "Great. Do you want to lock this first version now or answer one more setup question?",
      suggestions: [
        { id: "readiness:ready_to_commit", label: "Lock this first version now" },
        { id: "refine:customer_flow", label: "One more question about customer flow" },
      ],
      why_question: "post_capability_nuance_probe",
    };
  }

  return {
    assistant_message: "Pick the next detail to lock for your first version.",
    suggestions: [
      { id: "refine:pricing_rules", label: "Pricing and payment rules" },
      { id: "refine:booking_rules", label: "Booking and scheduling rules" },
      { id: "refine:user_roles", label: "User roles and permissions" },
      { id: "none_fit", label: "None fit, I’ll describe it" },
    ],
    why_question: "default_blocker_reduction",
  };
}

function sanitizeQuestionPlan(plan: NextQuestionPlan): NextQuestionPlan {
  let assistantMessage = plan.assistant_message
    .replace(/selection:\d+/gi, "that option")
    .replace(/selection:[^\s'"]+/gi, "that option")
    .replace(/artifact/gi, "website context")
    .replace(/checkpoint/gi, "confirmation step")
    .replace(/\s{2,}/g, " ")
    .trim();

  if (assistantMessage.toLowerCase().includes("what specific website context")) {
    assistantMessage = "I reviewed your website context. Please confirm or correct it in the card below.";
  }

  const suggestions = plan.suggestions.map((suggestion) => ({
    ...suggestion,
    label: suggestion.label
      .replace(/artifact/gi, "website context")
      .replace(/checkpoint/gi, "confirmation")
      .replace(/\s{2,}/g, " ")
      .trim(),
  }));

  return {
    assistant_message: assistantMessage,
    suggestions,
    why_question: plan.why_question,
  };
}

function latestDecisionByKey(decisions: DecisionItem[]): Record<string, DecisionItem> {
  const map: Record<string, DecisionItem> = {};
  for (const decision of decisions) {
    if (!map[decision.decision_key]) {
      map[decision.decision_key] = decision;
    }
  }
  return map;
}

function isDecisionConfirmed(decision?: DecisionItem): boolean {
  if (!decision) return false;
  return decision.status === "USER_SAID" && decision.lock_state === "locked" && Boolean(decision.confirmed_by_turn_id);
}

function deriveControlState(input: {
  selectedOptionId: string;
  suggestionsCount: number;
  unresolvedCount: number;
}): ControlState {
  if (isArtifactVerificationSelection(input.selectedOptionId)) {
    return {
      postureMode: "Verification",
      moveType: "MOVE_REFLECT_VERIFY",
      burdenSignal: "low",
      paceSignal: "opening",
      transitionReason: "artifact_confirmation_response",
    };
  }

  if (input.selectedOptionId && input.suggestionsCount > 0) {
    return {
      postureMode: "Alignment Checkpoint",
      moveType: "MOVE_ALIGNMENT_CHECKPOINT",
      burdenSignal: "low",
      paceSignal: "narrowing",
      transitionReason: "explicit_checkpoint_selection",
    };
  }

  if (input.unresolvedCount > 3) {
    return {
      postureMode: "Extraction",
      moveType: "MOVE_TARGETED_CLARIFY",
      burdenSignal: "medium",
      paceSignal: "reopening",
      transitionReason: "high_unresolved_count",
    };
  }

  return {
    postureMode: "Exploration",
    moveType: "MOVE_OPEN_DISCOVER",
    burdenSignal: "medium",
    paceSignal: "opening",
    transitionReason: "default_exploration",
  };
}

function inferBusinessTypeFromText(input: string): string | null {
  const lowered = input.toLowerCase();
  if (lowered.includes("photography")) return "photography";
  if (lowered.includes("coach")) return "coaching";
  if (lowered.includes("consult")) return "consulting";
  if (lowered.includes("meal")) return "meal services";
  if (lowered.includes("ecommerce") || lowered.includes("e-commerce") || lowered.includes("store")) return "e-commerce";
  if (lowered.includes("app") || lowered.includes("software") || lowered.includes("saas")) return "software";
  return null;
}

function isArtifactVerificationSelection(selectedOptionId: string): boolean {
  return selectedOptionId === "artifact_verify:right"
    || selectedOptionId === "artifact_verify:mostly"
    || selectedOptionId === "artifact_verify:wrong"
    || selectedOptionId === "artifact_verify:proceed_uncertain"
    || selectedOptionId === "checkpoint:confirm"
    || selectedOptionId === "checkpoint:reject"
    || selectedOptionId === "checkpoint:partial"
    || selectedOptionId === "checkpoint:skip";
}

function hasUserSignaledScopeComplete(lowerText: string): boolean {
  const patterns = [
    "no more feature",
    "no more features",
    "any more feature",
    "any more features",
    "no additional feature",
    "no additional features",
    "thats enough",
    "that's enough",
    "ready to commit",
    "ready to finalize",
    "ready to submit",
  ];
  return patterns.some((pattern) => lowerText.includes(pattern));
}

function normalizeArtifactType(raw: string): string {
  const lowered = raw.toLowerCase();
  if (lowered === "website" || lowered === "brand_page" || lowered === "uploaded_doc" || lowered === "other") {
    return lowered;
  }
  return "website";
}

function hasConfirmedBusinessType(rows: Record<string, unknown>[]): boolean {
  return hasExplicitlyConfirmedBusinessType(rows);
}

function hasConfirmedDecision(rows: Record<string, unknown>[], key: string): boolean {
  return rows.some((row) =>
    String(row.decision_key ?? "") === key &&
    String(row.status ?? "") === "USER_SAID" &&
    String(row.lock_state ?? "") === "locked" &&
    String(row.confirmed_by_turn_id ?? "").trim().length > 0
  );
}

function hasCommitReadiness(rows: Record<string, unknown>[], artifactVerificationPending: boolean): boolean {
  if (artifactVerificationPending) return false;
  if (!hasConfirmedBusinessType(rows)) return false;
  if (!hasConfirmedDecision(rows, "primary_outcome")) return false;
  if (!hasConfirmedDecision(rows, "launch_capabilities")) return false;
  if (!hasConfirmedDecision(rows, "monetization_path")) return false;
  if (rows.some((row) => Boolean(row.has_conflict))) return false;
  return true;
}

function collectCommitBlockers(
  rows: Record<string, unknown>[],
  canCommit: boolean,
  artifactVerificationPending: boolean,
  qualityReady: boolean,
  signalState: SignalState,
): string[] {
  const blockers: string[] = [];
  if (canCommit) return blockers;

  if (!hasConfirmedBusinessType(rows)) blockers.push("Confirm your app type.");
  if (!hasConfirmedDecision(rows, "primary_outcome")) blockers.push("Confirm what users should do first.");
  if (!hasConfirmedDecision(rows, "launch_capabilities")) blockers.push("Select one or two version-one capabilities.");
  if (!hasConfirmedDecision(rows, "monetization_path")) blockers.push("Decide whether payments are needed in version one.");

  if (artifactVerificationPending) blockers.push("Verify your website context.");
  if (!qualityReady && hasConfirmedBusinessType(rows)) {
    const needed = Math.max(0, 3 - signalState.richEvidenceCount);
    blockers.push(
      needed > 0
        ? `Add ${needed} more plain-language setup answer(s) so the draft has enough detail.`
        : "Add one more plain-language setup answer so the draft has enough detail.",
    );
  }

  const conflictCount = rows.filter((row) => Boolean(row.has_conflict)).length;
  if (conflictCount > 0) blockers.push(`Resolve ${conflictCount} remaining contradiction(s).`);

  return blockers;
}

function normalizeStructuredSelection(selectedOptionId: string, noneFitText: string): { decisionKey: string; claim: string } | null {
  if (!selectedOptionId || selectedOptionId === "none_fit" || !selectedOptionId.includes(":")) return null;

  const [prefix, rawValue] = selectedOptionId.split(":", 2);
  const value = rawValue.replace(/_/g, " ").trim();
  if (!value) return null;

  switch (prefix) {
    case "outcome":
      return { decisionKey: "primary_outcome", claim: `Primary first action: ${value}.` };
    case "capability": {
      const secondary = extractSecondaryCapability(noneFitText);
      const claim = secondary
        ? `Version one capabilities: ${value} + ${secondary}.`
        : `Version one capability: ${value}.`;
      return { decisionKey: "launch_capabilities", claim };
    }
    case "monetization":
      return { decisionKey: "monetization_path", claim: `Monetization path: ${value}.` };
    case "audience":
      return { decisionKey: "primary_audience", claim: `Primary audience: ${value}.` };
    case "readiness":
      return { decisionKey: "draft_readiness_ack", claim: `Readiness preference: ${value}.` };
    case "refine":
      return { decisionKey: "refinement_focus", claim: `Refinement focus: ${value}.` };
    case "quality":
      return { decisionKey: "quality_signal", claim: `Quality focus confirmed: ${value}.` };
    default:
      return null;
  }
}

function extractSecondaryCapability(noneFitText: string): string | null {
  const trimmed = noneFitText.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^Secondary priority:\s*(.+)\.?$/i);
  if (!match) return null;
  return match[1].trim();
}

function buildReadinessState(input: {
  decisions: DecisionItem[];
  unresolvedCount: number;
  checkpointPending: boolean;
  hasArtifactContext: boolean;
  artifactVerified: boolean;
  qualityReady: boolean;
  signalState: SignalState;
}): ReadinessState {
  const byKey = latestDecisionByKey(input.decisions);
  const buckets: ReadinessBucket[] = [
    readinessBucket("business_type", "Business type", isDecisionConfirmed(byKey["business_type"]), "Confirm what kind of app this is."),
    readinessBucket("primary_outcome", "First customer outcome", isDecisionConfirmed(byKey["primary_outcome"]), "Lock what users should do first."),
    readinessBucket("launch_capabilities", "Version one capabilities", isDecisionConfirmed(byKey["launch_capabilities"]), "Choose one or two core capabilities."),
    readinessBucket("monetization_path", "Payment approach", isDecisionConfirmed(byKey["monetization_path"]), "Decide payments now vs later."),
    artifactReadinessBucket(input.hasArtifactContext, input.artifactVerified, input.checkpointPending),
    qualityReadinessBucket(input.qualityReady, input.signalState),
  ];

  const resolved = buckets.filter((bucket) => bucket.status === "resolved").length;
  const total = buckets.length;
  const score = Math.round((resolved / total) * 100);

  const nextFocus = buckets.find((bucket) => bucket.status !== "resolved")?.label ?? "Ready for draft commit review";

  return {
    score,
    resolved_count: resolved,
    total_count: total,
    next_focus: nextFocus,
    buckets,
  };
}

function qualityReadinessBucket(qualityReady: boolean, signalState: SignalState): ReadinessBucket {
  if (qualityReady) {
    return {
      key: "quality_signal",
      label: "Draft quality signal",
      status: "resolved",
      detail: "Enough plain-language detail captured for a strong first draft.",
    };
  }
  return {
    key: "quality_signal",
    label: "Draft quality signal",
    status: "missing",
    detail: `Answer ${Math.max(1, 3 - signalState.richEvidenceCount)} more easy setup question(s).`,
  };
}

function buildSignalState(turns: IntakeTurn[]): SignalState {
  const userTurns = turns.filter((turn) => turn.actor_type === "USER");
  const richEvidenceCount = userTurns.filter((turn) => isRichEvidenceTurn(turn.raw_text)).length;
  const hasOpenEvidence = userTurns.some((turn) => {
    const text = turn.raw_text.trim().toLowerCase();
    if (!text) return false;
    return !text.startsWith("selection:") && !text.startsWith("artifact verification:");
  });
  return {
    userTurnCount: userTurns.length,
    richEvidenceCount,
    hasOpenEvidence,
  };
}

function isRichEvidenceTurn(raw: string): boolean {
  const text = raw.trim();
  if (!text) return false;
  const lower = text.toLowerCase();
  if (lower.startsWith("selection:") || lower.startsWith("artifact verification:")) return false;
  if (text.includes("http://") || text.includes("https://")) return false;
  return text.length >= 24;
}

function hasQualityReadiness(coreReady: boolean, signalState: SignalState, rows: Record<string, unknown>[]): boolean {
  if (!coreReady) return false;
  if (hasConfirmedDecision(rows, "quality_signal")) return true;
  if (signalState.richEvidenceCount >= 3) return true;
  if (signalState.richEvidenceCount >= 2 && signalState.userTurnCount >= 6) return true;
  return false;
}

function buildQualityQuestionPlan(signalState: SignalState): NextQuestionPlan {
  return {
    assistant_message: "Choose one final setup area to lock before generating your first draft plan.",
    suggestions: [
      { id: "quality:customer_flow", label: "How customers should move through your app" },
      { id: "quality:operations", label: "What you need to manage day to day" },
      { id: "quality:trust", label: "What must feel trustworthy to users" },
      { id: "quality:brand_feel", label: "How the app should feel and sound" },
      { id: "none_fit", label: "None fit, I’ll describe it" },
    ],
    why_question: "quality_signal_gap",
  };
}

function readinessBucket(key: string, label: string, resolved: boolean, detail: string): ReadinessBucket {
  return {
    key,
    label,
    status: resolved ? "resolved" : "missing",
    detail: resolved ? "Locked by explicit user confirmation." : detail,
  };
}

function artifactReadinessBucket(hasArtifact: boolean, artifactVerified: boolean, checkpointPending: boolean): ReadinessBucket {
  if (!hasArtifact) {
    return {
      key: "website_context",
      label: "Website context (optional)",
      status: "in_progress",
      detail: "Optional. Add a website if you want faster grounding.",
    };
  }

  if (checkpointPending || !artifactVerified) {
    return {
      key: "website_context",
      label: "Website context",
      status: "missing",
      detail: "Confirm or correct the website understanding.",
    };
  }

  return {
    key: "website_context",
    label: "Website context",
    status: "resolved",
    detail: "Website understanding verified.",
  };
}

async function persistReadinessSnapshot(
  serviceClient: ReturnType<typeof createClient>,
  input: { projectId: string; cycleNo: number; turnId: string; readiness: ReadinessState },
) {
  const { error } = await serviceClient.from("interview_readiness_snapshots").insert({
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    turn_id: input.turnId,
    readiness_score: input.readiness.score,
    resolved_count: input.readiness.resolved_count,
    total_count: input.readiness.total_count,
    next_focus: input.readiness.next_focus,
    bucket_states: input.readiness.buckets,
  });

  if (error) {
    const code = String(error.code ?? "");
    if (code === "42P01") {
      console.log("[next-turn] readiness_snapshot_table_missing");
      return;
    }
    console.log(`[next-turn] readiness_snapshot_insert_error=${code}:${String(error.message ?? "unknown")}`);
  }
}

async function upsertSemanticEntryForTurn(
  serviceClient: ReturnType<typeof createClient>,
  input: {
    openAIKey: string;
    projectId: string;
    cycleNo: number;
    turnId: string;
    sourceText: string;
    brainVersion: string;
  },
) {
  if (!input.openAIKey || input.sourceText.trim().length < 12) return;

  const vector = await generateEmbedding(input.openAIKey, input.sourceText);
  if (!vector || vector.length === 0) return;

  const { error } = await serviceClient.from("interview_semantic_entries").upsert({
    project_id: input.projectId,
    cycle_no: input.cycleNo,
    source_type: "intake_turn",
    source_id: input.turnId,
    source_text: input.sourceText,
    embedding: vector,
    embedding_model: "text-embedding-3-small",
    brain_version: input.brainVersion,
    provenance_refs: [`turn:${input.turnId}`],
  }, { onConflict: "project_id,cycle_no,source_type,source_id,embedding_model" });

  if (error) {
    const code = String(error.code ?? "");
    if (code === "42P01") {
      console.log("[next-turn] semantic_entries_table_missing");
      return;
    }
    console.log(`[next-turn] semantic_entries_upsert_error=${code}:${String(error.message ?? "unknown")}`);
  }
}

async function generateEmbedding(openAIKey: string, text: string): Promise<number[] | null> {
  try {
    const response = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: text.slice(0, 4000),
      }),
    });
    if (!response.ok) return null;
    const payload = await response.json();
    const embedding = payload?.data?.[0]?.embedding;
    if (!Array.isArray(embedding)) return null;
    return embedding.map((value: unknown) => Number(value)).filter((value: number) => Number.isFinite(value));
  } catch {
    return null;
  }
}

function resolveUserText(userMessageRaw: string, selectedOptionId: string, noneFitText: string): string {
  if (userMessageRaw) return userMessageRaw;
  if (selectedOptionId === "none_fit") return noneFitText;
  if (selectedOptionId.startsWith("artifact_verify:") || selectedOptionId.startsWith("checkpoint:")) {
    if (noneFitText) return noneFitText;
    return `artifact verification: ${selectedOptionId.replace("artifact_verify:", "").replace("checkpoint:", "")}`;
  }
  if (selectedOptionId.includes(":")) {
    return selectedOptionId.split(":").slice(1).join(":").replace(/_/g, " ");
  }
  return noneFitText;
}

function normalizeCheckpointResponseInput(
  rawValue: unknown,
  selectedOptionId: string,
  noneFitText: string,
): CheckpointResponseInput | null {
  const actionFromSelected = mapCheckpointAction(selectedOptionId);
  if (actionFromSelected) {
    const optionalText = noneFitText.trim();
    return {
      action: actionFromSelected,
      optional_text: optionalText.length > 0 ? optionalText : undefined,
    };
  }

  if (!rawValue || typeof rawValue !== "object") return null;
  const raw = rawValue as Record<string, unknown>;
  const checkpointId = String(raw.checkpoint_id ?? "").trim();
  const actionRaw = String(raw.action ?? "").trim().toLowerCase();
  const action = normalizeCheckpointAction(actionRaw);
  if (!action) return null;
  const optionalText = String(raw.optional_text ?? "").trim();
  return {
    checkpoint_id: checkpointId || undefined,
    action,
    optional_text: optionalText.length > 0 ? optionalText : undefined,
  };
}

function normalizeCheckpointAction(input: string): CheckpointAction | null {
  switch (input) {
    case "confirm":
      return "confirm";
    case "reject":
      return "reject";
    case "partial":
      return "partial";
    case "skip":
      return "skip";
    default:
      return null;
  }
}

function mapCheckpointAction(optionId: string): CheckpointAction | null {
  if (!optionId.startsWith("checkpoint:")) return null;
  const suffix = optionId.replace("checkpoint:", "");
  return normalizeCheckpointAction(suffix);
}

function inferCheckpointActionFromText(input: string): CheckpointAction | null {
  const text = input.trim().toLowerCase();
  if (!text) return null;
  if (/^(yes|y|correct|right|that'?s right|looks right|sounds right)\b/.test(text)) return "confirm";
  if (/^(no|n|wrong|incorrect|not right|that'?s wrong)\b/.test(text)) return "reject";
  if (/^(partially|partial|mostly|refine|needs correction)\b/.test(text)) return "partial";
  if (/^(skip|not sure|unsure)\b/.test(text)) return "skip";
  return null;
}

function canonicalizeCheckpointUrl(raw: string): string {
  const safe = canonicalizeUrl(raw);
  if (safe.ok) return safe.url;
  return raw.trim().toLowerCase();
}

function buildArtifactCheckpointPrompt(input: {
  artifact: ArtifactInputRow;
  statusMessage: string | null;
  hasStoredRefs: boolean;
}): string {
  const status = input.statusMessage ? `${input.statusMessage} ` : "";
  const summary = input.artifact.summary_text && input.artifact.summary_text.trim().length > 0
    ? input.artifact.summary_text.trim()
    : "I do not yet have enough extracted site text to summarize with confidence.";
  const provenancePhrase = input.hasStoredRefs
    ? "Based only on stored extracted website text, here is my current understanding:"
    : "I do not yet have reliable extracted website text.";
  return `${status}${provenancePhrase} ${summary} Is this understanding correct?`;
}

function normalizeCheckpointOptions(rawOptions: unknown, fallback: Suggestion[]): Suggestion[] {
  if (!Array.isArray(rawOptions)) return fallback;
  const options = rawOptions
    .map((item) => {
      const row = item as Record<string, unknown>;
      const id = String(row.id ?? "").trim();
      const label = String(row.label ?? "").trim();
      return { id, label };
    })
    .filter((item) => item.id.length > 0 && item.label.length > 0)
    .slice(0, 4);
  return options.length > 0 ? options : fallback;
}

function toCheckpointRow(row: Record<string, unknown>): CheckpointRow {
  const statusRaw = String(row.status ?? "pending");
  const status = (statusRaw === "pending" || statusRaw === "confirmed" || statusRaw === "rejected" || statusRaw === "skipped")
    ? statusRaw
    : "pending";
  return {
    id: String(row.id),
    checkpoint_type: String(row.checkpoint_type ?? "artifact_verification"),
    checkpoint_key: String(row.checkpoint_key ?? ""),
    status,
    payload: (typeof row.payload === "object" && row.payload !== null)
      ? (row.payload as Record<string, unknown>)
      : {},
  };
}

function buildPendingCheckpointPlan(checkpoint: NextTurnCheckpoint): NextQuestionPlan {
  return {
    assistant_message: "Please confirm the website context card to continue.",
    suggestions: [],
    why_question: `checkpoint_pending:${checkpoint.type}`,
  };
}

async function sha256String(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeHost(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return "invalid_supabase_url";
  }
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
