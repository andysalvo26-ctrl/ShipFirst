import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { BriefDoc, SlotKey, SlotValue } from "./kodos_v6_engine.ts";
import { createEmbedding, hashSource } from "./kodos_v6_engine.ts";

export type ProjectRow = {
  id: string;
  owner_user_id: string;
  title: string;
  idea_sentence: string;
  website_url: string | null;
  readiness_state: "not_ready" | "ready";
  active_revision: number;
  updated_at: string;
};

export async function loadProject(service: SupabaseClient, projectId: string): Promise<ProjectRow | null> {
  const { data, error } = await service
    .from("kodos_v6_projects")
    .select("id,owner_user_id,title,idea_sentence,website_url,readiness_state,active_revision,updated_at")
    .eq("id", projectId)
    .maybeSingle();

  if (error || !data) return null;
  return data as ProjectRow;
}

export function ensureProjectOwner(project: ProjectRow | null, userId: string): { ok: boolean; reason?: string } {
  if (!project) return { ok: false, reason: "Project not found." };
  if (project.owner_user_id !== userId) return { ok: false, reason: "Project does not belong to current user." };
  return { ok: true };
}

export async function loadSlotMap(
  service: SupabaseClient,
  projectId: string,
  revisionNo: number,
): Promise<Partial<Record<SlotKey, SlotValue>>> {
  const { data } = await service
    .from("kodos_v6_slot_states")
    .select("slot_key,slot_label,slot_value,slot_status,confidence,evidence")
    .eq("project_id", projectId)
    .eq("revision_no", revisionNo);

  const slotMap: Partial<Record<SlotKey, SlotValue>> = {};
  for (const row of data ?? []) {
    const key = String(row.slot_key ?? "") as SlotKey;
    if (!key) continue;
    slotMap[key] = {
      slotKey: key,
      slotLabel: String(row.slot_label ?? key),
      value: String(row.slot_value ?? ""),
      status: normalizeSlotStatus(String(row.slot_status ?? "captured")),
      confidence: Number(row.confidence ?? 0),
      evidence: Array.isArray(row.evidence) ? row.evidence.map((item) => String(item)) : [],
    };
  }

  return slotMap;
}

export async function upsertSlotValues(
  service: SupabaseClient,
  projectId: string,
  revisionNo: number,
  updates: Partial<Record<SlotKey, SlotValue>>,
  sourceTurnId: string | null,
): Promise<void> {
  const rows = Object.values(updates)
    .filter((entry): entry is SlotValue => Boolean(entry && entry.slotKey && entry.value))
    .map((entry) => ({
      project_id: projectId,
      revision_no: revisionNo,
      slot_key: entry.slotKey,
      slot_label: entry.slotLabel,
      slot_value: entry.value,
      slot_status: entry.status,
      confidence: entry.confidence,
      source_turn_id: sourceTurnId,
      evidence: entry.evidence,
    }));

  if (rows.length === 0) return;

  await service
    .from("kodos_v6_slot_states")
    .upsert(rows, { onConflict: "project_id,revision_no,slot_key" });
}

export async function appendTurn(
  service: SupabaseClient,
  input: {
    projectId: string;
    revisionNo: number;
    actor: "user" | "system";
    messageText: string;
    answerKind: "idea" | "option" | "free_text" | "system";
    questionKey?: string | null;
    selectedOptionId?: string | null;
  },
): Promise<{ id: string } | null> {
  const { data, error } = await service
    .from("kodos_v6_turns")
    .insert({
      project_id: input.projectId,
      revision_no: input.revisionNo,
      actor: input.actor,
      message_text: input.messageText,
      answer_kind: input.answerKind,
      question_key: input.questionKey ?? null,
      selected_option_id: input.selectedOptionId ?? null,
    })
    .select("id")
    .single();

  if (error || !data) return null;
  return { id: String(data.id) };
}

export async function upsertMemoryChunk(
  service: SupabaseClient,
  input: {
    openAIKey: string;
    projectId: string;
    revisionNo: number;
    sourceTable: string;
    sourceRowId: string;
    chunkText: string;
    metadata?: Record<string, unknown>;
  },
): Promise<void> {
  const sourceHash = hashSource(input.chunkText);
  const embedding = await createEmbedding(input.openAIKey, input.chunkText);

  await service
    .from("kodos_v6_memory_chunks")
    .upsert(
      {
        project_id: input.projectId,
        revision_no: input.revisionNo,
        source_table: input.sourceTable,
        source_row_id: input.sourceRowId,
        source_hash: sourceHash,
        chunk_text: input.chunkText,
        embedding,
        model_version: "text-embedding-3-small",
        is_stale: false,
        metadata: input.metadata ?? {},
      },
      { onConflict: "project_id,source_table,source_row_id,source_hash,model_version" },
    );
}

export async function fetchMemoryHighlights(
  service: SupabaseClient,
  input: {
    openAIKey: string;
    projectId: string;
    revisionNo: number;
    queryText: string;
    limit?: number;
  },
): Promise<string[]> {
  const limit = Math.max(1, Math.min(input.limit ?? 5, 8));
  const queryEmbedding = await createEmbedding(input.openAIKey, input.queryText);

  if (queryEmbedding && queryEmbedding.length > 0) {
    const { data } = await service.rpc("kodos_v6_match_memory_chunks", {
      p_project_id: input.projectId,
      p_revision_no: input.revisionNo,
      p_query_embedding: queryEmbedding,
      p_match_count: limit,
    });

    const highlights = (data ?? [])
      .map((row: Record<string, unknown>) => String(row.chunk_text ?? "").trim())
      .filter((text: string) => text.length > 0)
      .slice(0, limit);

    if (highlights.length > 0) return highlights;
  }

  const { data: recentTurns } = await service
    .from("kodos_v6_turns")
    .select("message_text")
    .eq("project_id", input.projectId)
    .eq("revision_no", input.revisionNo)
    .eq("actor", "user")
    .order("created_at", { ascending: false })
    .limit(limit);

  return (recentTurns ?? [])
    .map((row: Record<string, unknown>) => String(row.message_text ?? "").trim())
    .filter((item) => item.length > 0);
}

export async function updateProjectReadiness(
  service: SupabaseClient,
  projectId: string,
  readinessState: "not_ready" | "ready",
): Promise<void> {
  await service
    .from("kodos_v6_projects")
    .update({ readiness_state: readinessState })
    .eq("id", projectId);
}

export async function insertQuestionEvent(
  service: SupabaseClient,
  input: {
    projectId: string;
    revisionNo: number;
    questionKey: string;
    questionText: string;
    options: Array<{ id: string; label: string }>;
    selectedOptionId?: string | null;
    freeText?: string | null;
    answered?: boolean;
  },
): Promise<void> {
  await service
    .from("kodos_v6_question_events")
    .insert({
      project_id: input.projectId,
      revision_no: input.revisionNo,
      question_key: input.questionKey,
      question_text: input.questionText,
      options: input.options,
      selected_option_id: input.selectedOptionId ?? null,
      free_text: input.freeText ?? null,
      answered_at: input.answered ? new Date().toISOString() : null,
    });
}

export async function appendAuditEvent(
  service: SupabaseClient,
  input: {
    projectId?: string | null;
    revisionNo?: number | null;
    eventType: string;
    actor: "user" | "system";
    correlationId?: string | null;
    payload?: Record<string, unknown>;
  },
): Promise<void> {
  await service
    .from("kodos_v6_audit_events")
    .insert({
      project_id: input.projectId ?? null,
      revision_no: input.revisionNo ?? null,
      event_type: input.eventType,
      actor: input.actor,
      correlation_id: input.correlationId ?? null,
      payload: input.payload ?? {},
    });
}

export async function latestBriefSummary(
  service: SupabaseClient,
  projectId: string,
  revisionNo: number,
): Promise<{ versionNo: number; createdAt: string; docs: BriefDoc[] } | null> {
  const { data: versionRow } = await service
    .from("kodos_v6_brief_versions")
    .select("id,version_no,created_at")
    .eq("project_id", projectId)
    .eq("revision_no", revisionNo)
    .order("version_no", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!versionRow) return null;

  const { data: docs } = await service
    .from("kodos_v6_brief_docs")
    .select("doc_key,title,body")
    .eq("brief_version_id", versionRow.id)
    .order("doc_key", { ascending: true });

  const normalizedDocs: BriefDoc[] = (docs ?? []).map((row: Record<string, unknown>) => ({
    key: String(row.doc_key ?? "app_vision_brief") as BriefDoc["key"],
    title: String(row.title ?? ""),
    body: String(row.body ?? ""),
  }));

  return {
    versionNo: Number(versionRow.version_no ?? 1),
    createdAt: String(versionRow.created_at ?? ""),
    docs: normalizedDocs,
  };
}

export async function nextBriefVersionNo(service: SupabaseClient, projectId: string, revisionNo: number): Promise<number> {
  const { data } = await service
    .from("kodos_v6_brief_versions")
    .select("version_no")
    .eq("project_id", projectId)
    .eq("revision_no", revisionNo)
    .order("version_no", { ascending: false })
    .limit(1)
    .maybeSingle();

  return Number(data?.version_no ?? 0) + 1;
}

function normalizeSlotStatus(value: string): SlotValue["status"] {
  if (value === "assumed") return "assumed";
  if (value === "confirmed") return "confirmed";
  return "captured";
}
