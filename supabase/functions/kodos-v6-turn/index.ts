import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  chooseNextQuestion,
  CORS_HEADERS,
  evaluateReadiness,
  fail,
  jsonResponse,
  maybePersonalizeQuestion,
  slotDefinition,
  type SlotKey,
  updateFromAnswer,
} from "../_shared/kodos_v6_engine.ts";
import {
  appendAuditEvent,
  appendTurn,
  ensureProjectOwner,
  fetchMemoryHighlights,
  insertQuestionEvent,
  loadProject,
  loadSlotMap,
  updateProjectReadiness,
  upsertMemoryChunk,
  upsertSlotValues,
} from "../_shared/kodos_v6_store.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const openAIKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    const llmModel = Deno.env.get("SHIPFIRST_LLM_MODEL") ?? "gpt-4o-mini";

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return fail(500, "SERVER_CONFIG_MISSING", "Missing Supabase server environment.", "server");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
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
    const questionKey = String(payload.question_key ?? "").trim() as SlotKey;
    const selectedOptionId = String(payload.selected_option_id ?? "").trim();
    const freeText = String(payload.free_text ?? "").trim();
    const correlationId = String(payload.correlation_id ?? crypto.randomUUID());

    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");
    if (!questionKey && !freeText) {
      return fail(400, "ANSWER_REQUIRED", "Please pick an option or add a short text answer.", "validation");
    }

    const service = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const project = await loadProject(service, projectId);
    const ownership = ensureProjectOwner(project, userId);
    if (!ownership.ok) {
      const status = project ? 403 : 404;
      const code = project ? "PROJECT_FORBIDDEN" : "PROJECT_NOT_FOUND";
      const layer = project ? "authorization" : "validation";
      return fail(status, code, ownership.reason ?? "Project access error.", layer);
    }

    const revisionNo = Number(project?.active_revision ?? 1);

    const answerLabel = selectedOptionLabel(questionKey, selectedOptionId);
    const answerText = freeText || answerLabel || selectedOptionId || "";

    const userTurn = await appendTurn(service, {
      projectId,
      revisionNo,
      actor: "user",
      messageText: answerText,
      answerKind: freeText ? "free_text" : "option",
      questionKey: questionKey || null,
      selectedOptionId: selectedOptionId || null,
    });

    if (!userTurn) {
      return fail(500, "TURN_WRITE_FAILED", "Could not save your answer.", "schema");
    }

    await upsertMemoryChunk(service, {
      openAIKey,
      projectId,
      revisionNo,
      sourceTable: "kodos_v6_turns",
      sourceRowId: userTurn.id,
      chunkText: answerText,
      metadata: {
        actor: "user",
        question_key: questionKey,
        selected_option_id: selectedOptionId,
      },
    });

    const slotUpdates = updateFromAnswer({
      questionKey,
      selectedOptionId,
      freeText,
      fallbackMessage: answerText,
    });

    await upsertSlotValues(service, projectId, revisionNo, slotUpdates, userTurn.id);

    const slotMap = await loadSlotMap(service, projectId, revisionNo);
    const readiness = evaluateReadiness(slotMap);
    await updateProjectReadiness(service, projectId, readiness.state);

    let nextQuestion = chooseNextQuestion(slotMap, true);
    if (nextQuestion && project) {
      const highlights = await fetchMemoryHighlights(service, {
        openAIKey,
        projectId,
        revisionNo,
        queryText: nextQuestion.prompt,
        limit: 4,
      });
      nextQuestion = await maybePersonalizeQuestion({
        openAIKey,
        model: llmModel,
        question: nextQuestion,
        ideaSentence: project.idea_sentence,
        memoryHighlights: highlights,
      });
    }

    await insertQuestionEvent(service, {
      projectId,
      revisionNo,
      questionKey: questionKey || "free_text",
      questionText: questionKey ? slotDefinition(questionKey).prompt : "Open response",
      options: questionKey ? slotDefinition(questionKey).options.map((option) => ({ id: option.id, label: option.label })) : [],
      selectedOptionId: selectedOptionId || null,
      freeText: freeText || null,
      answered: true,
    });

    if (nextQuestion) {
      await insertQuestionEvent(service, {
        projectId,
        revisionNo,
        questionKey: nextQuestion.key,
        questionText: nextQuestion.prompt,
        options: nextQuestion.options,
        answered: false,
      });
    }

    await appendAuditEvent(service, {
      projectId,
      revisionNo,
      eventType: "answer_saved",
      actor: "user",
      correlationId,
      payload: {
        question_key: questionKey,
        readiness_state: readiness.state,
      },
    });

    return jsonResponse({
      project_id: projectId,
      revision_no: revisionNo,
      readiness,
      next_question: nextQuestion,
      can_generate: readiness.state === "ready",
      can_improve: readiness.missingOptional.length > 0,
      status_message: readiness.state === "ready"
        ? "Ready to generate your 3-document plan."
        : "Nice. Keep going with one more quick detail.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown server error.";
    return fail(500, "SERVER_ERROR", message, "server");
  }
});

function selectedOptionLabel(questionKey: string, selectedOptionId: string): string {
  if (!questionKey || !selectedOptionId) return "";
  const slot = slotDefinition(questionKey as SlotKey);
  const option = slot.options.find((item) => item.id === selectedOptionId);
  return option?.value ?? option?.label ?? "";
}
