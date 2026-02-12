import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  chooseNextQuestion,
  CORS_HEADERS,
  evaluateReadiness,
  fail,
  inferSlotsFromIdea,
  jsonResponse,
  maybePersonalizeQuestion,
  slotDefinition,
  type SlotValue,
} from "../_shared/kodos_v6_engine.ts";
import {
  appendAuditEvent,
  appendTurn,
  ensureProjectOwner,
  fetchMemoryHighlights,
  insertQuestionEvent,
  latestBriefSummary,
  loadProject,
  loadSlotMap,
  updateProjectReadiness,
  upsertMemoryChunk,
  upsertSlotValues,
} from "../_shared/kodos_v6_store.ts";

type Action = "list" | "create" | "get";

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
    const action = normalizeAction(payload.action);
    const correlationId = String(payload.correlation_id ?? crypto.randomUUID());

    const service = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === "list") {
      return await listProjects(service, userId);
    }

    if (action === "create") {
      const title = String(payload.title ?? "").trim();
      const ideaSentence = String(payload.idea_sentence ?? "").trim();
      const websiteUrl = normalizeOptionalText(payload.website_url);

      if (!title) return fail(400, "TITLE_REQUIRED", "Project title is required.", "validation");
      if (!ideaSentence) return fail(400, "IDEA_REQUIRED", "Idea sentence is required.", "validation");

      const { data: project, error: projectError } = await service
        .from("kodos_v6_projects")
        .insert({
          owner_user_id: userId,
          title,
          idea_sentence: ideaSentence,
          website_url: websiteUrl,
          readiness_state: "not_ready",
          active_revision: 1,
        })
        .select("id,owner_user_id,title,idea_sentence,website_url,readiness_state,active_revision,updated_at")
        .single();

      if (projectError || !project) return failFromDb(projectError, "kodos_v6_projects.insert");

      const revisionNo = Number(project.active_revision ?? 1);
      const initialTurn = await appendTurn(service, {
        projectId: String(project.id),
        revisionNo,
        actor: "user",
        messageText: ideaSentence,
        answerKind: "idea",
      });

      if (initialTurn) {
        await upsertMemoryChunk(service, {
          openAIKey,
          projectId: String(project.id),
          revisionNo,
          sourceTable: "kodos_v6_turns",
          sourceRowId: initialTurn.id,
          chunkText: ideaSentence,
          metadata: { actor: "user", answer_kind: "idea" },
        });
      }

      const slotUpdates: Partial<Record<string, SlotValue>> = inferSlotsFromIdea(ideaSentence);
      if (websiteUrl && !slotUpdates.brand_style) {
        slotUpdates.brand_style = {
          slotKey: "brand_style",
          slotLabel: slotDefinition("brand_style").label,
          value: "Clean and modern",
          status: "captured",
          confidence: 0.5,
          evidence: [websiteUrl],
        };
      }

      await upsertSlotValues(service, String(project.id), revisionNo, slotUpdates, initialTurn?.id ?? null);

      const slotMap = await loadSlotMap(service, String(project.id), revisionNo);
      const readiness = evaluateReadiness(slotMap);
      await updateProjectReadiness(service, String(project.id), readiness.state);

      let question = chooseNextQuestion(slotMap, true);
      if (question) {
        const highlights = await fetchMemoryHighlights(service, {
          openAIKey,
          projectId: String(project.id),
          revisionNo,
          queryText: question.prompt,
          limit: 4,
        });
        question = await maybePersonalizeQuestion({
          openAIKey,
          model: llmModel,
          question,
          ideaSentence,
          memoryHighlights: highlights,
        });

        await insertQuestionEvent(service, {
          projectId: String(project.id),
          revisionNo,
          questionKey: question.key,
          questionText: question.prompt,
          options: question.options,
        });
      }

      await appendAuditEvent(service, {
        projectId: String(project.id),
        revisionNo,
        eventType: "project_created",
        actor: "user",
        correlationId,
        payload: { readiness: readiness.state },
      });

      return jsonResponse({
        project: {
          id: project.id,
          title: project.title,
          idea_sentence: project.idea_sentence,
          website_url: project.website_url,
          readiness_state: readiness.state,
          active_revision: revisionNo,
          updated_at: project.updated_at,
        },
        state: {
          readiness,
          next_question: question,
          can_generate: readiness.state === "ready",
          can_improve: readiness.missingOptional.length > 0,
          status_message: readiness.state === "ready"
            ? "Ready to generate your 3-document plan."
            : "Keep going. We need a few more basics.",
        },
      });
    }

    const projectId = String(payload.project_id ?? "").trim();
    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");

    const project = await loadProject(service, projectId);
    const ownership = ensureProjectOwner(project, userId);
    if (!ownership.ok) {
      const status = project ? 403 : 404;
      const code = project ? "PROJECT_FORBIDDEN" : "PROJECT_NOT_FOUND";
      const layer: ErrorLayer = project ? "authorization" : "validation";
      return fail(status, code, ownership.reason ?? "Project access error.", layer);
    }

    const revisionNo = Number(project?.active_revision ?? 1);
    const slotMap = await loadSlotMap(service, projectId, revisionNo);
    const readiness = evaluateReadiness(slotMap);

    let question = chooseNextQuestion(slotMap, true);
    if (question && project) {
      const highlights = await fetchMemoryHighlights(service, {
        openAIKey,
        projectId,
        revisionNo,
        queryText: question.prompt,
        limit: 4,
      });
      question = await maybePersonalizeQuestion({
        openAIKey,
        model: llmModel,
        question,
        ideaSentence: project.idea_sentence,
        memoryHighlights: highlights,
      });
    }

    const briefSummary = await latestBriefSummary(service, projectId, revisionNo);

    return jsonResponse({
      project: {
        id: project?.id,
        title: project?.title,
        idea_sentence: project?.idea_sentence,
        website_url: project?.website_url,
        readiness_state: readiness.state,
        active_revision: revisionNo,
        updated_at: project?.updated_at,
      },
      state: {
        readiness,
        next_question: question,
        can_generate: readiness.state === "ready",
        can_improve: readiness.missingOptional.length > 0,
        status_message: readiness.state === "ready"
          ? "Ready to generate your 3-document plan."
          : "Keep going. We need a few more basics.",
      },
      latest_brief: briefSummary
        ? {
          version_no: briefSummary.versionNo,
          created_at: briefSummary.createdAt,
          docs: briefSummary.docs,
        }
        : null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown server error.";
    return fail(500, "SERVER_ERROR", message, "server");
  }
});

async function listProjects(service: ReturnType<typeof createClient>, userId: string): Promise<Response> {
  const { data: projects, error } = await service
    .from("kodos_v6_projects")
    .select("id,title,idea_sentence,website_url,readiness_state,active_revision,updated_at")
    .eq("owner_user_id", userId)
    .order("updated_at", { ascending: false })
    .limit(60);

  if (error) return failFromDb(error, "kodos_v6_projects.list");

  const projectIDs = (projects ?? []).map((row) => String(row.id));
  const versionByProject = new Map<string, number>();

  if (projectIDs.length > 0) {
    const { data: versions } = await service
      .from("kodos_v6_brief_versions")
      .select("project_id,version_no")
      .in("project_id", projectIDs)
      .order("version_no", { ascending: false });

    for (const row of versions ?? []) {
      const projectId = String(row.project_id ?? "");
      if (!projectId || versionByProject.has(projectId)) continue;
      versionByProject.set(projectId, Number(row.version_no ?? 0));
    }
  }

  const items = (projects ?? []).map((row) => {
    const projectId = String(row.id);
    const latestVersion = versionByProject.get(projectId) ?? 0;
    return {
      id: projectId,
      title: String(row.title ?? "Untitled"),
      idea_sentence: String(row.idea_sentence ?? ""),
      website_url: row.website_url ? String(row.website_url) : null,
      readiness_state: String(row.readiness_state ?? "not_ready"),
      active_revision: Number(row.active_revision ?? 1),
      updated_at: String(row.updated_at ?? ""),
      has_brief: latestVersion > 0,
      latest_version_no: latestVersion > 0 ? latestVersion : null,
    };
  });

  return jsonResponse({ projects: items });
}

function normalizeAction(value: unknown): Action {
  const normalized = String(value ?? "list").trim().toLowerCase();
  if (normalized === "create") return "create";
  if (normalized === "get") return "get";
  return "list";
}

function normalizeOptionalText(value: unknown): string | null {
  const trimmed = String(value ?? "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function failFromDb(error: { code?: string; message?: string } | null, operation: string): Response {
  const code = String(error?.code ?? "DB_ERROR");
  const message = String(error?.message ?? `Database operation failed: ${operation}`);
  return fail(500, code, message, "schema", { operation });
}
