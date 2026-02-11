#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "verify_interview_engine_contract: FAIL - $1" >&2
  exit 1
}

check_file() {
  local file="$1"
  [[ -f "${ROOT_DIR}/${file}" ]] || fail "missing file: ${file}"
}

check_file "supabase/functions/next-turn/index.ts"
check_file "supabase/functions/commit-contract/index.ts"
check_file "supabase/migrations/20260211020000_interview_engine_state_support.sql"
check_file "supabase/migrations/20260211043000_interview_checkpoints.sql"
check_file "supabase/migrations/20260211130000_kodos_readiness_semantic_state.sql"

NEXT_TURN_FILE="${ROOT_DIR}/supabase/functions/next-turn/index.ts"
COMMIT_CONTRACT_FILE="${ROOT_DIR}/supabase/functions/commit-contract/index.ts"
MIGRATION_FILE="${ROOT_DIR}/supabase/migrations/20260211020000_interview_engine_state_support.sql"
CHECKPOINT_MIGRATION_FILE="${ROOT_DIR}/supabase/migrations/20260211043000_interview_checkpoints.sql"
READINESS_MIGRATION_FILE="${ROOT_DIR}/supabase/migrations/20260211130000_kodos_readiness_semantic_state.sql"

echo "verify_interview_engine_contract: check 1/8 migration includes required interview engine tables/columns"
grep -q "create table if not exists public.artifact_inputs" "${MIGRATION_FILE}" || fail "artifact_inputs table not found in migration"
grep -q "create table if not exists public.interview_turn_state" "${MIGRATION_FILE}" || fail "interview_turn_state table not found in migration"
grep -q "add column if not exists confirmed_by_turn_id" "${MIGRATION_FILE}" || fail "decision_items.confirmed_by_turn_id not found in migration"
grep -q "add column if not exists hypothesis_rationale" "${MIGRATION_FILE}" || fail "decision_items.hypothesis_rationale not found in migration"
grep -q "create table if not exists public.interview_checkpoints" "${CHECKPOINT_MIGRATION_FILE}" || fail "interview_checkpoints table not found in checkpoint migration"
grep -q "create table if not exists public.interview_readiness_snapshots" "${READINESS_MIGRATION_FILE}" || fail "interview_readiness_snapshots table missing in readiness migration"
grep -q "create table if not exists public.interview_semantic_entries" "${READINESS_MIGRATION_FILE}" || fail "interview_semantic_entries table missing in readiness migration"

echo "verify_interview_engine_contract: check 2/8 no silent heuristic promotion to USER_SAID+locked"
if perl -0777 -ne 'exit 1 if /inferBusinessTypeFromText\(.*?status:\s*"USER_SAID".*?lock_state:\s*"locked"/s' "${NEXT_TURN_FILE}"; then
  :
else
  fail "heuristic inference appears to promote USER_SAID+locked"
fi
grep -q "confirmed_by_turn_id" "${NEXT_TURN_FILE}" || fail "next-turn missing confirmed_by_turn_id linkage"

echo "verify_interview_engine_contract: check 3/8 next-turn response contract includes posture + move"
grep -q "posture_mode:" "${NEXT_TURN_FILE}" || fail "next-turn response missing posture_mode"
grep -q "move_type:" "${NEXT_TURN_FILE}" || fail "next-turn response missing move_type"
grep -q "readiness:" "${NEXT_TURN_FILE}" || fail "next-turn response missing readiness state"
grep -q "trace:" "${NEXT_TURN_FILE}" || fail "next-turn response missing trace block"

echo "verify_interview_engine_contract: check 4/8 artifact-first verification path present"
grep -q "resolveOrCreateCheckpoint" "${NEXT_TURN_FILE}" || fail "checkpoint resolver missing"
grep -q "checkpoint:" "${NEXT_TURN_FILE}" || fail "next-turn response missing checkpoint object"
grep -q "requires_response" "${NEXT_TURN_FILE}" || fail "checkpoint requires_response contract missing"
grep -q "artifact_requires_comprehension_verification" "${NEXT_TURN_FILE}" || fail "artifact-first transition reason missing"
grep -q "buildPendingCheckpointPlan" "${NEXT_TURN_FILE}" || fail "pending checkpoint planner missing"

echo "verify_interview_engine_contract: check 5/8 business-type gate predicate is shared and explicit"
grep -q "hasExplicitlyConfirmedBusinessType" "${NEXT_TURN_FILE}" || fail "next-turn does not use shared business-type confirmation predicate"
grep -q "hasExplicitlyConfirmedBusinessType" "${COMMIT_CONTRACT_FILE}" || fail "commit-contract does not use shared business-type confirmation predicate"
grep -q "confirmed_by_turn_id" "${COMMIT_CONTRACT_FILE}" || fail "commit-contract gate path missing confirmed_by_turn_id requirement"
if rg -n "BUSINESS_TYPE_UNCONFIRMED" "${COMMIT_CONTRACT_FILE}" | rg -q "decision_state"; then
  fail "commit-contract still gates BUSINESS_TYPE_UNCONFIRMED via decision_state"
fi

echo "verify_interview_engine_contract: check 6/8 checkpoint response handling is explicit and prevents repeat prompt"
grep -q "normalizeCheckpointResponseInput" "${NEXT_TURN_FILE}" || fail "next-turn missing checkpoint_response parsing"
grep -q "inferCheckpointActionFromText" "${NEXT_TURN_FILE}" || fail "next-turn missing free-text fallback for pending checkpoint"
grep -q "verification_state: verificationState" "${NEXT_TURN_FILE}" || fail "artifact verification_state not updated from checkpoint action"
grep -q "checkpoint: null" "${NEXT_TURN_FILE}" || fail "resolved checkpoint does not clear pending state in response"

echo "verify_interview_engine_contract: check 7/8 cycle_no handling is payload-aware in both endpoints"
grep -q "const cycleNoInput = Number(payload.cycle_no ?? 0);" "${NEXT_TURN_FILE}" || fail "next-turn missing payload cycle_no parsing"
grep -q "const cycleNoInput = Number(payload.cycle_no ?? 0);" "${COMMIT_CONTRACT_FILE}" || fail "commit-contract missing payload cycle_no parsing"
grep -q "const cycleNo = cycleNoInput >= 1 ? cycleNoInput : Number(projectRow.active_cycle_no ?? 1);" "${NEXT_TURN_FILE}" || fail "next-turn missing canonical cycle resolution"
grep -q "const cycleNo = cycleNoInput >= 1 ? cycleNoInput : Number(projectRow.active_cycle_no ?? 1);" "${COMMIT_CONTRACT_FILE}" || fail "commit-contract missing canonical cycle resolution"

echo "verify_interview_engine_contract: check 8/8 commit-contract has no submission side effects"
if rg -n "\\.from\\(\"submission_artifacts\"\\)\\s*\\.(insert|upsert|update)" "${COMMIT_CONTRACT_FILE}" >/dev/null; then
  fail "commit-contract writes to submission_artifacts; submit must remain explicit"
fi
if rg -n "shipfirst-submissions|storage\\.upload|submission\\.bundle_uploaded" "${COMMIT_CONTRACT_FILE}" >/dev/null; then
  fail "commit-contract references submission upload flow; submit must remain explicit"
fi

echo "verify_interview_engine_contract: PASS"
