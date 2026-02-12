import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  CORS_HEADERS,
  evaluateReadiness,
  fail,
  generateBrief,
  jsonResponse,
  REQUIRED_SLOT_KEYS,
  wordCount,
} from "../_shared/kodos_v6_engine.ts";
import {
  appendAuditEvent,
  ensureProjectOwner,
  fetchMemoryHighlights,
  loadProject,
  loadSlotMap,
  nextBriefVersionNo,
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
    const modeInput = String(payload.mode ?? payload.generation_mode ?? "fast").trim().toLowerCase();
    const mode = modeInput === "improve" ? "improve" : "fast";
    const correlationId = String(payload.correlation_id ?? crypto.randomUUID());

    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");

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
    const slotMap = await loadSlotMap(service, projectId, revisionNo);
    const readiness = evaluateReadiness(slotMap);

    const resolvedRequiredCount = REQUIRED_SLOT_KEYS.filter((key) => slotMap[key]).length;
    if (resolvedRequiredCount < 3) {
      return fail(
        409,
        "NOT_ENOUGH_INPUT",
        "We need at least three core answers before generation.",
        "validation",
        { missing_required: readiness.missingRequired },
      );
    }

    const memoryHighlights = await fetchMemoryHighlights(service, {
      openAIKey,
      projectId,
      revisionNo,
      queryText: `${project?.idea_sentence ?? ""}\nGenerate App Vision Brief, MVP Blueprint, Owner Control Brief`,
      limit: 8,
    });

    const generated = await generateBrief({
      openAIKey,
      model: llmModel,
      title: project?.title ?? "Untitled Project",
      ideaSentence: project?.idea_sentence ?? "",
      websiteUrl: project?.website_url,
      slotMap,
      memoryHighlights,
      generationMode: mode,
    });

    const versionNo = await nextBriefVersionNo(service, projectId, revisionNo);

    const { data: versionRow, error: versionError } = await service
      .from("kodos_v6_brief_versions")
      .insert({
        project_id: projectId,
        revision_no: revisionNo,
        version_no: versionNo,
        generation_mode: mode,
        readiness_state: readiness.state,
        source_snapshot: {
          slot_map: slotMap,
          memory_highlights: memoryHighlights,
        },
        internal_build_contract: generated.internalBuildContract,
      })
      .select("id,created_at")
      .single();

    if (versionError || !versionRow) {
      return fail(500, "BRIEF_VERSION_INSERT_FAILED", versionError?.message ?? "Could not save brief version.", "schema");
    }

    for (const doc of generated.docs) {
      const { error: docError } = await service
        .from("kodos_v6_brief_docs")
        .insert({
          project_id: projectId,
          revision_no: revisionNo,
          brief_version_id: versionRow.id,
          doc_key: doc.key,
          title: doc.title,
          body: doc.body,
          word_count: wordCount(doc.body),
        });

      if (docError) {
        return fail(500, "BRIEF_DOC_INSERT_FAILED", docError.message, "schema", { doc_key: doc.key });
      }
    }

    await appendAuditEvent(service, {
      projectId,
      revisionNo,
      eventType: "brief_generated",
      actor: "system",
      correlationId,
      payload: {
        version_no: versionNo,
        mode,
        readiness_state: readiness.state,
      },
    });

    return jsonResponse({
      project_id: projectId,
      revision_no: revisionNo,
      version_no: versionNo,
      created_at: versionRow.created_at,
      generation_mode: mode,
      readiness,
      docs: generated.docs,
      summary: {
        title: project?.title,
        can_generate: true,
        generated_doc_count: generated.docs.length,
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown server error.";
    return fail(500, "SERVER_ERROR", message, "server");
  }
});
