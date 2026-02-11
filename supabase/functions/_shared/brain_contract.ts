import { ROLE_IDS, ROLE_META, isTrustLabel, type TrustLabel } from "./roles.ts";

export type RoleBudget = {
  softTarget: number;
  hardMin: number;
  hardMax: number;
};

export const ROLE_BUDGETS: Record<number, RoleBudget> = {
  1: { softTarget: 120, hardMin: 90, hardMax: 150 },
  2: { softTarget: 220, hardMin: 170, hardMax: 270 },
  3: { softTarget: 160, hardMin: 120, hardMax: 200 },
  4: { softTarget: 220, hardMin: 170, hardMax: 280 },
  5: { softTarget: 220, hardMin: 170, hardMax: 280 },
  6: { softTarget: 160, hardMin: 120, hardMax: 210 },
  7: { softTarget: 180, hardMin: 140, hardMax: 230 },
  8: { softTarget: 180, hardMin: 140, hardMax: 240 },
  9: { softTarget: 220, hardMin: 170, hardMax: 280 },
  10: { softTarget: 220, hardMin: 170, hardMax: 280 },
};

export type VersionTuple = {
  prompt_pack_version: string;
  state_machine_version: string;
  record_contract_version: string;
  ten_docs_contract_version: string;
  validation_profile_version: string;
  retrieval_profile_version: string;
};

export type GeneratedClaim = {
  claim_text: string;
  trust_label: TrustLabel;
  provenance_refs: string[];
};

export type GeneratedDoc = {
  role_id: number;
  title: string;
  body: string;
  claims: GeneratedClaim[];
};

export type ValidationIssue = {
  code: string;
  severity: "block" | "warn" | "info";
  message: string;
  role_id?: number;
};

const SPINE_SECTIONS = [
  "purpose",
  "key decisions",
  "acceptance criteria",
  "success measures",
  "unknowns",
  "builder notes",
];

export function canonicalizeVersionTuple(tuple: VersionTuple): string {
  return [
    `prompt_pack_version=${tuple.prompt_pack_version}`,
    `state_machine_version=${tuple.state_machine_version}`,
    `record_contract_version=${tuple.record_contract_version}`,
    `ten_docs_contract_version=${tuple.ten_docs_contract_version}`,
    `validation_profile_version=${tuple.validation_profile_version}`,
    `retrieval_profile_version=${tuple.retrieval_profile_version}`,
  ].join("|");
}

export async function sha256(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function buildRunIdentity(stage: string, inputFingerprint: string, tuple: VersionTuple): string {
  const tupleSlug = canonicalizeVersionTuple(tuple);
  return `${stage}:${inputFingerprint}:${tupleSlug}`;
}

export function wordCount(text: string): number {
  const normalized = text.trim();
  if (!normalized) return 0;
  return normalized.split(/\s+/).length;
}

export function countBuilderNotes(body: string): number {
  const lines = body.split("\n");
  const start = lines.findIndex((line) => line.trim().toLowerCase() === "builder notes");
  if (start < 0) return 0;

  let count = 0;
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line) continue;

    const lower = line.toLowerCase();
    if (
      lower === "purpose" ||
      lower === "key decisions" ||
      lower === "acceptance criteria" ||
      lower === "success measures" ||
      lower === "unknowns"
    ) {
      break;
    }

    if (line.startsWith("- ")) {
      count += 1;
    }
  }

  return count;
}

export function normalizeRefs(refs: string[] | null | undefined, fallbackRef: string): string[] {
  const clean = (refs ?? []).map((ref) => String(ref).trim()).filter(Boolean);
  if (clean.length > 0) return clean;
  return [fallbackRef];
}

function missingSpine(body: string): string[] {
  const normalized = body.toLowerCase();
  return SPINE_SECTIONS.filter((section) => !normalized.includes(section));
}

export function validateTenDocPacket(docs: GeneratedDoc[]): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (docs.length !== 10) {
    issues.push({
      code: "ROLE_COUNT",
      severity: "block",
      message: `Exactly 10 documents required, got ${docs.length}.`,
    });
  }

  const roleSet = new Set(docs.map((doc) => doc.role_id));
  const missingRoles = ROLE_IDS.filter((roleID) => !roleSet.has(roleID));
  if (missingRoles.length > 0) {
    issues.push({
      code: "MISSING_ROLES",
      severity: "block",
      message: `Missing required role IDs: ${missingRoles.join(", ")}.`,
    });
  }

  const extraRoles = Array.from(roleSet).filter((roleID) => !ROLE_IDS.includes(roleID as (typeof ROLE_IDS)[number]));
  if (extraRoles.length > 0) {
    issues.push({
      code: "EXTRA_ROLES",
      severity: "block",
      message: `Unexpected role IDs: ${extraRoles.join(", ")}.`,
    });
  }

  for (const doc of docs) {
    if (!ROLE_IDS.includes(doc.role_id as (typeof ROLE_IDS)[number])) continue;

    const budget = ROLE_BUDGETS[doc.role_id];
    const count = wordCount(doc.body);

    if (count < budget.hardMin || count > budget.hardMax) {
      issues.push({
        code: "BUDGET_HARD",
        severity: "block",
        role_id: doc.role_id,
        message: `Role ${doc.role_id} word budget out of bounds (${count}, expected ${budget.hardMin}-${budget.hardMax}).`,
      });
    } else if (count < budget.softTarget * 0.75 || count > budget.softTarget * 1.25) {
      issues.push({
        code: "BUDGET_SOFT",
        severity: "warn",
        role_id: doc.role_id,
        message: `Role ${doc.role_id} word budget drift (${count}) from soft target ${budget.softTarget}.`,
      });
    }

    const notesCount = countBuilderNotes(doc.body);
    if (notesCount < 3 || notesCount > 6) {
      issues.push({
        code: "BUILDER_NOTES_COUNT",
        severity: "block",
        role_id: doc.role_id,
        message: `Role ${doc.role_id} requires 3-6 Builder Notes bullets, found ${notesCount}.`,
      });
    }

    const spineMissing = missingSpine(doc.body);
    if (spineMissing.length > 0) {
      issues.push({
        code: "SPINE_MISSING",
        severity: "block",
        role_id: doc.role_id,
        message: `Role ${doc.role_id} missing required spine sections: ${spineMissing.join(", ")}.`,
      });
    }

    if (!Array.isArray(doc.claims) || doc.claims.length === 0) {
      issues.push({
        code: "CLAIMS_MISSING",
        severity: "block",
        role_id: doc.role_id,
        message: `Role ${doc.role_id} must contain at least one claim.`,
      });
      continue;
    }

    for (const claim of doc.claims) {
      if (!isTrustLabel(claim.trust_label)) {
        issues.push({
          code: "TRUST_LABEL_INVALID",
          severity: "block",
          role_id: doc.role_id,
          message: `Role ${doc.role_id} has claim with invalid trust label.`,
        });
      }

      if (!claim.claim_text || !claim.claim_text.trim()) {
        issues.push({
          code: "CLAIM_BLANK",
          severity: "block",
          role_id: doc.role_id,
          message: `Role ${doc.role_id} has blank claim text.`,
        });
      }

      if (!Array.isArray(claim.provenance_refs) || claim.provenance_refs.length === 0) {
        issues.push({
          code: "PROVENANCE_MISSING",
          severity: "block",
          role_id: doc.role_id,
          message: `Role ${doc.role_id} has claim missing provenance refs.`,
        });
      }
    }
  }

  return issues;
}

export function hasUnknownClaims(docs: GeneratedDoc[]): boolean {
  return docs.some((doc) => doc.claims.some((claim) => claim.trust_label === "UNKNOWN"));
}

export type ManifestDocMeta = {
  role_id: number;
  role_key: string;
  title: string;
  claim_count: number;
  created_at: string;
  content_hash?: string;
};

export function buildSubmissionManifest(input: {
  run_id: string;
  project_id: string;
  cycle_no: number;
  user_id: string;
  contract_version_id: string;
  contract_version_number: number;
  submitted_at: string;
  docs: ManifestDocMeta[];
  version_tuple: Record<string, unknown>;
  packet_hash?: string;
}): Record<string, unknown> {
  return {
    run_id: input.run_id,
    project_id: input.project_id,
    cycle_no: input.cycle_no,
    user_id: input.user_id,
    contract_version_id: input.contract_version_id,
    contract_version_number: input.contract_version_number,
    submitted_at: input.submitted_at,
    document_count: input.docs.length,
    version_tuple: input.version_tuple,
    packet_hash: input.packet_hash ?? null,
    documents: input.docs.map((doc) => ({
      role_id: doc.role_id,
      role_key: doc.role_key,
      title: doc.title,
      claim_count: doc.claim_count,
      created_at: doc.created_at,
      content_hash: doc.content_hash ?? null,
    })),
  };
}

export function roleTitle(roleID: number): string {
  return ROLE_META[roleID]?.title ?? `Role ${roleID}`;
}
