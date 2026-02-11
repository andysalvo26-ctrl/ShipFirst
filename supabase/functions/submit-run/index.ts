import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { ROLE_IDS, ROLE_META, normalizeTrustLabel } from "../_shared/roles.ts";
import {
  buildSubmissionManifest,
  sha256,
  validateTenDocPacket,
  type GeneratedDoc,
  type GeneratedClaim,
} from "../_shared/brain_contract.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ErrorLayer = "auth" | "authorization" | "validation" | "schema" | "transient" | "server";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) return fail(500, "SERVER_CONFIG_MISSING", "Missing server environment.", "server");

    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseHost = (() => {
      try {
        return new URL(supabaseUrl).hostname;
      } catch {
        return "invalid_supabase_url";
      }
    })();
    console.log(`[submit-run] supabase_host=${supabaseHost}`);
    console.log(`[submit-run] auth_header_length=${authHeader.length}`);
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
    const cycleNo = Number(payload.cycle_no ?? 1);
    const reviewConfirmed = Boolean(payload.review_confirmed ?? false);
    if (!projectId) return fail(400, "PROJECT_ID_REQUIRED", "project_id is required.", "validation");
    if (!reviewConfirmed) {
      return fail(409, "REVIEW_CONFIRMATION_REQUIRED", "Submit requires explicit review confirmation.", "validation");
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: projectRow, error: projectError } = await supabase
      .from("projects")
      .select("id,owner_user_id")
      .eq("id", projectId)
      .single();

    if (projectError || !projectRow) return fail(404, "PROJECT_NOT_FOUND", "Project not found.", "validation");
    if (projectRow.owner_user_id !== userId) return fail(403, "PROJECT_FORBIDDEN", "Project does not belong to current user.", "authorization");

    const { data: versionRow, error: versionError } = await supabase
      .from("contract_versions")
      .select("id,project_id,cycle_no,version_number,version_tuple")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("version_number", { ascending: false })
      .limit(1)
      .single();

    if (versionError || !versionRow) return fail(409, "SUBMIT_NO_COMMITTED_VERSION", "No committed contract version to submit.", "validation");

    const versionId = String((versionRow as Record<string, unknown>).id);

    const { data: docsRows, error: docsError } = await supabase
      .from("contract_docs")
      .select("id,project_id,cycle_no,contract_version_id,role_id,title,body,is_complete,created_at")
      .eq("contract_version_id", versionId)
      .order("role_id", { ascending: true });

    if (docsError) return failFromDbError(docsError, "contract_docs.select");

    const { data: reqRows, error: reqError } = await supabase
      .from("requirements")
      .select("id,project_id,cycle_no,contract_version_id,contract_doc_id,role_id,requirement_text,trust_label,requirement_index")
      .eq("contract_version_id", versionId)
      .order("role_id", { ascending: true })
      .order("requirement_index", { ascending: true });

    if (reqError) return failFromDbError(reqError, "requirements.select");

    const { data: provRows, error: provError } = await supabase
      .from("provenance_links")
      .select("requirement_id,pointer")
      .eq("contract_version_id", versionId);

    if (provError) return failFromDbError(provError, "provenance_links.select");

    const refsByRequirement = new Map<string, string[]>();
    for (const row of provRows ?? []) {
      const reqID = String((row as Record<string, unknown>).requirement_id);
      refsByRequirement.set(reqID, [...(refsByRequirement.get(reqID) ?? []), String((row as Record<string, unknown>).pointer)]);
    }

    const reqsByDoc = new Map<string, Array<Record<string, unknown>>>();
    for (const req of reqRows ?? []) {
      const key = String((req as Record<string, unknown>).contract_doc_id);
      reqsByDoc.set(key, [...(reqsByDoc.get(key) ?? []), req as Record<string, unknown>]);
    }

    const docs = (docsRows ?? []).map((doc): GeneratedDoc => {
      const docID = String((doc as Record<string, unknown>).id);
      const claims = (reqsByDoc.get(docID) ?? []).map((req): GeneratedClaim => ({
        claim_text: String(req.requirement_text ?? ""),
        trust_label: normalizeTrustLabel(String(req.trust_label)) ?? "UNKNOWN",
        provenance_refs: refsByRequirement.get(String(req.id)) ?? [],
      }));

      return {
        role_id: Number((doc as Record<string, unknown>).role_id),
        title: String((doc as Record<string, unknown>).title),
        body: String((doc as Record<string, unknown>).body),
        claims,
      };
    });

    const validationIssues = validateTenDocPacket(docs);
    const blockingIssues = validationIssues.filter((issue) => issue.severity === "block");
    if (blockingIssues.length > 0) {
      return fail(409, "SUBMIT_VALIDATION_FAILED", "Submit validation failed.", "validation", { issues: blockingIssues });
    }

    const roleSet = new Set(docs.map((doc) => doc.role_id));
    if (!ROLE_IDS.every((id) => roleSet.has(id))) {
      return fail(409, "SUBMIT_ROLE_SET_INVALID", "Submit failed role validation for roles 1..10.", "validation");
    }

    const now = new Date().toISOString();

    const docArtifacts = await Promise.all((docsRows ?? []).map(async (doc) => {
      const roleID = Number((doc as Record<string, unknown>).role_id);
      const roleKey = ROLE_META[roleID].key;
      const roleSlug = roleKey.toLowerCase();
      const title = String((doc as Record<string, unknown>).title);
      const createdAt = String((doc as Record<string, unknown>).created_at);
      const docID = String((doc as Record<string, unknown>).id);
      const reqCount = (reqsByDoc.get(String((doc as Record<string, unknown>).id)) ?? []).length;
      const claimLines = (reqsByDoc.get(docID) ?? [])
        .map((req) => {
          const refs = (refsByRequirement.get(String(req.id)) ?? []).join(", ");
          return `- [${String(req.trust_label ?? "UNKNOWN")}] ${String(req.requirement_text ?? "")} (provenance: ${refs})`;
        })
        .join("\n");

      const markdown = [
        `# ${roleID}. ${ROLE_META[roleID].title}`,
        "",
        String((doc as Record<string, unknown>).body),
        "",
        "## Claims",
        claimLines,
        "",
      ].join("\n");

      const contentHash = await sha256(markdown);

      return {
        roleID,
        roleKey,
        roleSlug,
        title,
        createdAt,
        claimCount: reqCount,
        markdown,
        contentHash,
      };
    }));

    const docsMeta = docArtifacts.map((artifact) => ({
      role_id: artifact.roleID,
      role_key: artifact.roleKey,
      title: artifact.title,
      claim_count: artifact.claimCount,
      created_at: artifact.createdAt,
      content_hash: artifact.contentHash,
    }));

    const packetHash = await sha256(JSON.stringify({
      project_id: projectId,
      cycle_no: cycleNo,
      contract_version_id: versionId,
      docs: docsMeta,
    }));

    const manifest = buildSubmissionManifest({
      run_id: `${projectId}:${cycleNo}`,
      project_id: projectId,
      cycle_no: cycleNo,
      user_id: userId,
      contract_version_id: versionId,
      contract_version_number: Number((versionRow as Record<string, unknown>).version_number),
      submitted_at: now,
      docs: docsMeta,
      version_tuple: ((versionRow as Record<string, unknown>).version_tuple ?? {}) as Record<string, unknown>,
      packet_hash: packetHash,
    });

    const zip = new JSZip();
    zip.file("manifest.json", JSON.stringify(manifest, null, 2));
    for (const artifact of docArtifacts) {
      zip.file(`${String(artifact.roleID).padStart(2, "0")}-${artifact.roleSlug}.md`, artifact.markdown);
    }

    const bytes = await zip.generateAsync({ type: "uint8array", compression: "DEFLATE" });
    const objectPath = `${userId}/${projectId}/cycle-${String(cycleNo).padStart(3, "0")}/version-${String((versionRow as Record<string, unknown>).version_number).padStart(4, "0")}/${versionId}/submission-${now.replace(/[:.]/g, "-")}.zip`;

    const { error: uploadError } = await supabase.storage
      .from("shipfirst-submissions")
      .upload(objectPath, bytes, { contentType: "application/zip", upsert: false });

    if (uploadError) return fail(400, "SUBMISSION_UPLOAD_FAILED", uploadError.message, "transient", { operation: "storage.upload" });

    const { data: submissionRow, error: submissionError } = await supabase
      .from("submission_artifacts")
      .upsert({
        project_id: projectId,
        cycle_no: cycleNo,
        contract_version_id: versionId,
        user_id: userId,
        bucket: "shipfirst-submissions",
        storage_path: objectPath,
        manifest,
        submitted_at: now,
      }, { onConflict: "contract_version_id" })
      .select("id")
      .single();

    if (submissionError || !submissionRow) {
      return failFromDbError(submissionError, "submission_artifacts.upsert", "Failed to record submission artifact.");
    }

    await supabase.from("audit_events").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      contract_version_id: versionId,
      actor_type: "SERVICE",
      actor_id: userId,
      event_type: "submission.bundle_uploaded",
      payload: {
        review_confirmed: true,
        submission_id: submissionRow.id,
        bucket: "shipfirst-submissions",
        path: objectPath,
        manifest_contract_version_id: versionId,
        packet_hash: packetHash,
      },
    });

    return json({
      submission_id: submissionRow.id,
      contract_version_id: versionId,
      bucket: "shipfirst-submissions",
      path: objectPath,
      submitted_at: now,
    });
  } catch (error) {
    return fail(500, "UNHANDLED_EXCEPTION", String(error), "server");
  }
});

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
