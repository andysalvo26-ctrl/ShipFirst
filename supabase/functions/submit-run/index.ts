import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { ROLE_IDS, ROLE_META, isTrustLabel } from "../_shared/roles.ts";
import {
  buildSubmissionManifest,
  validateTenDocPacket,
  type GeneratedDoc,
  type GeneratedClaim,
} from "../_shared/brain_contract.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) return json({ error: "Missing server environment." }, 500);

    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "").trim();
    if (!token) return json({ error: "Missing bearer token" }, 401);

    const payload = await req.json().catch(() => ({} as Record<string, unknown>));
    const projectId = String(payload.project_id ?? "").trim();
    const cycleNo = Number(payload.cycle_no ?? 1);
    if (!projectId) return json({ error: "project_id is required" }, 400);

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Unauthorized" }, 401);
    const userId = authData.user.id;

    const { data: projectRow, error: projectError } = await supabase
      .from("projects")
      .select("id,owner_user_id")
      .eq("id", projectId)
      .single();

    if (projectError || !projectRow) return json({ error: "Project not found" }, 404);
    if (projectRow.owner_user_id !== userId) return json({ error: "Forbidden" }, 403);

    const { data: versionRow, error: versionError } = await supabase
      .from("contract_versions")
      .select("id,project_id,cycle_no,version_number,version_tuple")
      .eq("project_id", projectId)
      .eq("cycle_no", cycleNo)
      .order("version_number", { ascending: false })
      .limit(1)
      .single();

    if (versionError || !versionRow) return json({ error: "No committed contract version to submit." }, 409);

    const versionId = String((versionRow as Record<string, unknown>).id);

    const { data: docsRows, error: docsError } = await supabase
      .from("contract_docs")
      .select("id,project_id,cycle_no,contract_version_id,role_id,title,body,is_complete,created_at")
      .eq("contract_version_id", versionId)
      .order("role_id", { ascending: true });

    if (docsError) return json({ error: docsError.message }, 400);

    const { data: reqRows, error: reqError } = await supabase
      .from("requirements")
      .select("id,project_id,cycle_no,contract_version_id,contract_doc_id,role_id,requirement_text,trust_label,requirement_index")
      .eq("contract_version_id", versionId)
      .order("role_id", { ascending: true })
      .order("requirement_index", { ascending: true });

    if (reqError) return json({ error: reqError.message }, 400);

    const { data: provRows, error: provError } = await supabase
      .from("provenance_links")
      .select("requirement_id,pointer")
      .eq("contract_version_id", versionId);

    if (provError) return json({ error: provError.message }, 400);

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
        trust_label: isTrustLabel(String(req.trust_label)) ? String(req.trust_label) as GeneratedClaim["trust_label"] : "UNKNOWN",
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
      return json({ error: "Submit validation failed.", issues: blockingIssues }, 409);
    }

    const roleSet = new Set(docs.map((doc) => doc.role_id));
    if (!ROLE_IDS.every((id) => roleSet.has(id))) {
      return json({ error: "Submit failed role validation for roles 1..10." }, 409);
    }

    const now = new Date().toISOString();
    const docsMeta = (docsRows ?? []).map((doc) => {
      const roleID = Number((doc as Record<string, unknown>).role_id);
      const reqCount = (reqsByDoc.get(String((doc as Record<string, unknown>).id)) ?? []).length;
      return {
        role_id: roleID,
        role_key: ROLE_META[roleID].key,
        title: String((doc as Record<string, unknown>).title),
        claim_count: reqCount,
        created_at: String((doc as Record<string, unknown>).created_at),
      };
    });

    const manifest = buildSubmissionManifest({
      run_id: `${projectId}:${cycleNo}`,
      user_id: userId,
      contract_version_id: versionId,
      contract_version_number: Number((versionRow as Record<string, unknown>).version_number),
      submitted_at: now,
      docs: docsMeta,
      version_tuple: ((versionRow as Record<string, unknown>).version_tuple ?? {}) as Record<string, unknown>,
    });

    const zip = new JSZip();
    zip.file("manifest.json", JSON.stringify(manifest, null, 2));

    for (const doc of docsRows ?? []) {
      const roleID = Number((doc as Record<string, unknown>).role_id);
      const roleKey = ROLE_META[roleID].key.toLowerCase();
      const docID = String((doc as Record<string, unknown>).id);
      const claimLines = (reqsByDoc.get(docID) ?? [])
        .map((req) => {
          const refs = (refsByRequirement.get(String(req.id)) ?? []).join(", ");
          return `- [${String(req.trust_label ?? "UNKNOWN")}] ${String(req.requirement_text ?? "")} (provenance: ${refs})`;
        })
        .join("\n");

      const md = [
        `# ${roleID}. ${ROLE_META[roleID].title}`,
        "",
        String((doc as Record<string, unknown>).body),
        "",
        "## Claims",
        claimLines,
        "",
      ].join("\n");

      zip.file(`${String(roleID).padStart(2, "0")}-${roleKey}.md`, md);
    }

    const bytes = await zip.generateAsync({ type: "uint8array", compression: "DEFLATE" });
    const objectPath = `${userId}/${projectId}/cycle-${String(cycleNo).padStart(3, "0")}/version-${String((versionRow as Record<string, unknown>).version_number).padStart(4, "0")}/${versionId}/submission-${now.replace(/[:.]/g, "-")}.zip`;

    const { error: uploadError } = await supabase.storage
      .from("shipfirst-submissions")
      .upload(objectPath, bytes, { contentType: "application/zip", upsert: false });

    if (uploadError) return json({ error: uploadError.message }, 400);

    await supabase
      .from("contract_versions")
      .update({ submission_bundle_path: objectPath, submitted_at: now, status: "submitted" })
      .eq("id", versionId);

    await supabase.from("audit_events").insert({
      project_id: projectId,
      cycle_no: cycleNo,
      contract_version_id: versionId,
      actor_type: "SERVICE",
      actor_id: userId,
      event_type: "submission.bundle_uploaded",
      payload: {
        bucket: "shipfirst-submissions",
        path: objectPath,
        manifest_contract_version_id: versionId,
      },
    });

    return json({
      submission_id: crypto.randomUUID(),
      contract_version_id: versionId,
      bucket: "shipfirst-submissions",
      path: objectPath,
      submitted_at: now,
    });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
