import {
  buildSubmissionManifest,
  canonicalizeVersionTuple,
  hasUnknownClaims,
  type GeneratedDoc,
  type VersionTuple,
  validateTenDocPacket,
} from "./brain_contract.ts";
import { ROLE_IDS, ROLE_META } from "./roles.ts";
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const tuple: VersionTuple = {
  prompt_pack_version: "brain-v1",
  state_machine_version: "sm-v1",
  record_contract_version: "record-v1",
  ten_docs_contract_version: "ten-v1",
  validation_profile_version: "val-v1",
  retrieval_profile_version: "ret-v1",
};

function validDoc(roleID: number): GeneratedDoc {
  return {
    role_id: roleID,
    title: ROLE_META[roleID].title,
    body: [
      "Purpose",
      "This role captures project intent with concrete context and constraints that map to execution quality and reliability outcomes.",
      "Key Decisions",
      "- [USER_SAID] The customer wants deterministic behavior for all critical outputs and review checkpoints.",
      "Acceptance Criteria",
      "- Role output is internally consistent and directly testable by the human builder without hidden assumptions.",
      "Success Measures",
      "- Review can trace claims to evidence and trust labels without ambiguity or silent invention.",
      "Unknowns",
      "- [UNKNOWN] Final compliance scope remains open until explicit user confirmation is captured.",
      "Builder Notes",
      "- Preserve UNKNOWN labels until direct confirmation event exists.",
      "- Keep provenance references explicit and non-empty per claim.",
      "- Keep role language concise and specific to this run.",
    ].join("\n"),
    claims: [
      {
        claim_text: "The customer requested deterministic review gates before submission.",
        trust_label: "USER_SAID",
        provenance_refs: ["turn:abc"],
      },
      {
        claim_text: "Compliance boundaries are unresolved and must remain explicit.",
        trust_label: "UNKNOWN",
        provenance_refs: ["decision:def"],
      },
    ],
  };
}

Deno.test("validateTenDocPacket passes with all 10 roles and required trust/provenance", () => {
  const docs = ROLE_IDS.map((id) => validDoc(id));
  const issues = validateTenDocPacket(docs);
  const blocks = issues.filter((issue) => issue.severity === "block");
  assertEquals(blocks.length, 0);
  assert(hasUnknownClaims(docs));
});

Deno.test("validateTenDocPacket blocks when a role is missing", () => {
  const docs = ROLE_IDS.slice(0, 9).map((id) => validDoc(id));
  const issues = validateTenDocPacket(docs);
  const roleIssue = issues.find((issue) => issue.code === "MISSING_ROLES");
  assert(roleIssue);
  assertEquals(roleIssue.severity, "block");
});

Deno.test("canonicalizeVersionTuple is stable and complete", () => {
  const canonical = canonicalizeVersionTuple(tuple);
  assertStringIncludes(canonical, "prompt_pack_version=brain-v1");
  assertStringIncludes(canonical, "ten_docs_contract_version=ten-v1");
  assertStringIncludes(canonical, "validation_profile_version=val-v1");
});

Deno.test("buildSubmissionManifest includes contract version and all 10 docs", () => {
  const docs = ROLE_IDS.map((id) => ({
    role_id: id,
    role_key: ROLE_META[id].key,
    title: ROLE_META[id].title,
    claim_count: 2,
    created_at: "2026-02-10T00:00:00Z",
    content_hash: `hash-${id}`,
  }));

  const manifest = buildSubmissionManifest({
    run_id: "run-1",
    project_id: "project-1",
    cycle_no: 1,
    user_id: "user-1",
    contract_version_id: "version-1",
    contract_version_number: 3,
    submitted_at: "2026-02-10T00:00:00Z",
    docs,
    version_tuple: tuple,
    packet_hash: "packet-hash",
  });

  assertEquals(manifest.run_id, "run-1");
  assertEquals(manifest.project_id, "project-1");
  assertEquals(manifest.cycle_no, 1);
  assertEquals(manifest.contract_version_id, "version-1");
  assertEquals(manifest.contract_version_number, 3);
  assertEquals(manifest.document_count, 10);
  assertEquals(manifest.packet_hash, "packet-hash");
});
