#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

XC_SUPABASE_URL="$(grep -E '^SUPABASE_URL' Config/Supabase.xcconfig | head -n1 | cut -d= -f2- | tr -d '[:space:]' | sed 's#:\\$()/#://#')"
XC_SUPABASE_ANON_KEY="$(grep -E '^SUPABASE_ANON_KEY' Config/Supabase.xcconfig | head -n1 | cut -d= -f2- | tr -d '[:space:]')"

export SUPABASE_URL="${SUPABASE_URL:-$XC_SUPABASE_URL}"
export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$XC_SUPABASE_ANON_KEY}"
export PROJECT_REF="${PROJECT_REF:-$(echo "$SUPABASE_URL" | sed -E 's#^https://([^.]+)\.supabase\.co/?$#\1#')}"

if [[ -z "${TEST_EMAIL:-}" || -z "${TEST_PASSWORD:-}" ]]; then
  echo "error: set TEST_EMAIL and TEST_PASSWORD in env" >&2
  exit 1
fi

VERIFY_PROJECT_NAME="${VERIFY_PROJECT_NAME:-ShipFirst Smoke Project $(date +%s)}"
SMOKE_ARTIFACT_URL="${SMOKE_ARTIFACT_URL:-https://example.com}"

curl -s "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" >/dev/null || true

ACCESS_TOKEN="$(curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" | jq -r '.access_token')"

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "error: failed to get ACCESS_TOKEN" >&2
  exit 1
fi

PROJECT_ID="$(curl -s "$SUPABASE_URL/rest/v1/projects?select=id,name,active_cycle_no&name=eq.$(printf %s "$VERIFY_PROJECT_NAME" | jq -sRr @uri)&order=created_at.asc&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq -r '.[0].id // empty')"

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(curl -s -X POST "$SUPABASE_URL/rest/v1/projects?select=id,name,active_cycle_no" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "{\"name\":\"$VERIFY_PROJECT_NAME\"}" | jq -r '.[0].id')"
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "error: failed to resolve PROJECT_ID" >&2
  exit 1
fi

CYCLE_NO="$(curl -s "$SUPABASE_URL/rest/v1/projects?id=eq.$PROJECT_ID&select=active_cycle_no" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq -r '.[0].active_cycle_no // 1')"

TURN_ARTIFACT="$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"user_message\":\"Use this website as context for my brand.\",\"artifact_ref\":\"$SMOKE_ARTIFACT_URL\",\"artifact_type\":\"website\"}")"

echo "$TURN_ARTIFACT" | jq -e '.posture_mode == "Artifact Grounding" and .move_type == "MOVE_REFLECT_VERIFY" and (.artifact != null) and (.checkpoint != null) and (.checkpoint.status == "pending") and (.checkpoint.requires_response == true)' >/dev/null
CHECKPOINT_ID="$(echo "$TURN_ARTIFACT" | jq -r '.checkpoint.id // empty')"
if [[ -z "$CHECKPOINT_ID" ]]; then
  echo "error: expected checkpoint id after artifact ingestion" >&2
  exit 1
fi

PAGES_COUNT="$(curl -s "$SUPABASE_URL/rest/v1/artifact_pages?project_id=eq.$PROJECT_ID&cycle_no=eq.$CYCLE_NO&select=id" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq 'length')"
SUMMARY_TEXT="$(echo "$TURN_ARTIFACT" | jq -r '.artifact.summary_text // ""')"
if [[ -n "$SUMMARY_TEXT" && "$PAGES_COUNT" -eq 0 ]]; then
  echo "error: summary returned without stored artifact_pages provenance" >&2
  exit 1
fi

TURN_ARTIFACT_CONFIRM="$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"checkpoint_response\":{\"checkpoint_id\":\"$CHECKPOINT_ID\",\"action\":\"confirm\"}}")"

echo "$TURN_ARTIFACT_CONFIRM" | jq -e '.checkpoint == null and .artifact.verification_state == "user_confirmed" and .posture_mode != "Artifact Grounding"' >/dev/null
if echo "$TURN_ARTIFACT_CONFIRM" | jq -r '.assistant_message // ""' | rg -q "Did I understand your site correctly"; then
  echo "error: repeated verification prompt after checkpoint confirmation" >&2
  exit 1
fi
CHECKPOINT_STATUS="$(curl -s "$SUPABASE_URL/rest/v1/interview_checkpoints?project_id=eq.$PROJECT_ID&cycle_no=eq.$CYCLE_NO&checkpoint_type=eq.artifact_verification&select=status&order=created_at.desc&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq -r '.[0].status // empty')"
if [[ "$CHECKPOINT_STATUS" != "confirmed" ]]; then
  echo "error: checkpoint status not confirmed after confirmation action" >&2
  exit 1
fi

TURN_1="$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"user_message\":\"I want to build a business.\"}")"

TURN_2="$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"selected_option_id\":\"business_type:photography\"}")"

BEFORE_CONFIRM="$(curl -s "$SUPABASE_URL/rest/v1/decision_items?project_id=eq.$PROJECT_ID&cycle_no=eq.$CYCLE_NO&decision_key=eq.business_type&select=status,lock_state,confirmed_by_turn_id&order=updated_at.desc&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")"
echo "$BEFORE_CONFIRM" | jq -e 'if length == 0 then true else (.[0].status != "USER_SAID" or (.[0].confirmed_by_turn_id != null)) end' >/dev/null

COMMIT="$(curl -s "$SUPABASE_URL/functions/v1/commit-contract" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO}")"

echo "$TURN_2" | jq -e '.can_commit == true' >/dev/null

AFTER_CONFIRM="$(curl -s "$SUPABASE_URL/rest/v1/decision_items?project_id=eq.$PROJECT_ID&cycle_no=eq.$CYCLE_NO&decision_key=eq.business_type&select=status,lock_state,confirmed_by_turn_id&order=updated_at.desc&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")"
echo "$AFTER_CONFIRM" | jq -e 'length > 0 and .[0].status == "USER_SAID" and .[0].lock_state == "locked" and (.[0].confirmed_by_turn_id != null)' >/dev/null

echo "$COMMIT" | jq -e '.contract_version_id != null and (.documents | length) == 10 and .review_required == true' >/dev/null

CONTRACT_VERSION_ID="$(echo "$COMMIT" | jq -r '.contract_version_id')"
PRE_SUBMISSION_COUNT="$(curl -s "$SUPABASE_URL/rest/v1/submission_artifacts?contract_version_id=eq.$CONTRACT_VERSION_ID&select=id" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq 'length')"
if [[ "$PRE_SUBMISSION_COUNT" -ne 0 ]]; then
  echo "error: commit produced submission side effects; expected explicit submit step" >&2
  exit 1
fi

SUBMIT="$(curl -s "$SUPABASE_URL/functions/v1/submit-run" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"review_confirmed\":true}")"
echo "$SUBMIT" | jq -e '.submission_id != null and .path != null and .submitted_at != null' >/dev/null

echo "$TURN_ARTIFACT" | jq '{step:"artifact", posture_mode, move_type, artifact: {ingest_state: .artifact.ingest_state, verification_state: .artifact.verification_state}}'
echo "$TURN_ARTIFACT_CONFIRM" | jq '{step:"artifact_confirm", posture_mode, move_type, checkpoint: (.checkpoint // null), artifact: {verification_state: .artifact.verification_state}}'
echo "$TURN_1" | jq '{step:"turn1", assistant_message, can_commit, commit_blockers, posture_mode, move_type}'
echo "$TURN_2" | jq '{step:"turn2", assistant_message, can_commit, commit_blockers, posture_mode, move_type}'
echo "$COMMIT" | jq '{step:"commit", contract_version_id, contract_version_number, review_required, doc_count:(.documents|length), submission:(.submission // null)}'
echo "$SUBMIT" | jq '{step:"submit", submission_id, contract_version_id, path, submitted_at}'
