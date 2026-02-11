# Verify ShipFirst v0 End-to-End

This verifies the canonical project/cycle flow:
`project_id + cycle_no -> next-turn interview loop -> commit-contract -> submission_artifacts + Storage bundle`.

## 0) DB contract gate (run first)

Run the deterministic contract verifier:

```bash
chmod +x scripts/verify_db_contract.sh
DATABASE_URL="postgresql://postgres:<password>@<host>:5432/postgres" ./scripts/verify_db_contract.sh
```

Expected:
- Required columns exist (including `projects.owner_user_id`, `decision_items.decision_key`, `decision_items.claim`, `contract_versions.version_number`).
- RLS is enabled for all customer-path control-plane tables.
- Required policies exist.

Quick SQL spot-check (manual):

```sql
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'projects' and column_name in ('id','owner_user_id','name')) or
    (table_name = 'decision_items' and column_name in ('project_id','cycle_no','decision_key','claim','status','decision_state','evidence_refs','lock_state','has_conflict')) or
    (table_name = 'contract_versions' and column_name in ('project_id','cycle_no','version_number'))
  )
order by table_name, column_name;

select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in (
    'projects','intake_turns','decision_items','generation_runs','contract_versions',
    'contract_docs','requirements','provenance_links','submission_artifacts','audit_events'
  )
order by tablename, policyname;
```

## 1) Preconditions

- Supabase project is linked and schema migrations applied.
- Edge functions are deployed.
- `supabase/functions/.env` secrets are set with `supabase secrets set --env-file supabase/functions/.env`.
- `jq` is installed locally.

## 1.1) Turn on runtime diagnostics (Xcode console)

Run the app in Debug and watch Xcode logs for:
- `[ShipFirstRuns] loadRuns ...` (session presence + token iat/exp)
- `[ShipFirstAPI] request.start ...` (operation/table/function)
- `[ShipFirstAPI] request.fail ...` (HTTP status + server payload)

Interpretation:
- `status=401` usually means missing/expired/invalid access token.
- `status=403` means access denied by policy/permissions for that operation.

## 2) Set local variables

```bash
XC_SUPABASE_URL=$(grep -E '^SUPABASE_URL' Config/Supabase.xcconfig | head -n1 | cut -d= -f2- | tr -d '[:space:]' | sed 's#:\$()/#://#')
XC_SUPABASE_ANON_KEY=$(grep -E '^SUPABASE_ANON_KEY' Config/Supabase.xcconfig | head -n1 | cut -d= -f2- | tr -d '[:space:]')

export SUPABASE_URL="${SUPABASE_URL:-$XC_SUPABASE_URL}"
export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$XC_SUPABASE_ANON_KEY}"
export PROJECT_REF="${PROJECT_REF:-$(echo "$SUPABASE_URL" | sed -E 's#^https://([^.]+)\.supabase\.co/?$#\1#')}"
export TEST_EMAIL="you@example.com"
export TEST_PASSWORD="change-me-123456"
```

## 3) Get an authenticated user token

```bash
curl -s "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" >/dev/null

ACCESS_TOKEN=$(curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" | jq -r '.access_token')

USER_ID=$(curl -s "$SUPABASE_URL/auth/v1/user" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.id')
```

Expected:
- `ACCESS_TOKEN` is non-empty.
- `USER_ID` is a UUID.

## 4) Reuse-or-create a project deterministically (start run cycle 1)

```bash
VERIFY_PROJECT_NAME="ShipFirst Verify Project"

PROJECT_ID=$(curl -s "$SUPABASE_URL/rest/v1/projects?select=id,name,active_cycle_no&name=eq.$(printf %s "$VERIFY_PROJECT_NAME" | jq -sRr @uri)&order=created_at.asc&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq -r '.[0].id // empty')

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(curl -s -X POST "$SUPABASE_URL/rest/v1/projects?select=id,name,active_cycle_no" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "{\"name\":\"$VERIFY_PROJECT_NAME\"}" | jq -r '.[0].id')
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "failed to resolve PROJECT_ID" >&2
  exit 1
fi

echo "using project_id=$PROJECT_ID"

CYCLE_NO=$(curl -s "$SUPABASE_URL/rest/v1/projects?id=eq.$PROJECT_ID&select=active_cycle_no" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json" | jq -r '.[0].active_cycle_no // 1')
```

Expected:
- `PROJECT_ID` is a UUID.

## 5) Drive the interview loop (conversation is never gate-blocked)

```bash
TURN1=$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"user_message\":\"I want to build a business.\"}")

echo "$TURN1" | jq '{assistant_message, options, can_commit, commit_blockers}'

TURN2=$(curl -s "$SUPABASE_URL/functions/v1/next-turn" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO,\"user_message\":\"A photography business.\"}")

echo "$TURN2" | jq '{assistant_message, options, can_commit, commit_blockers}'
```

Expected:
- Each call returns an assistant question and optional options.
- No hard validation gate should block `next-turn` for normal conversation.

## 6) Confirm intake turns are append-only and actor-tagged

```bash
curl -s "$SUPABASE_URL/rest/v1/intake_turns?project_id=eq.$PROJECT_ID&cycle_no=eq.$CYCLE_NO&select=id,turn_index,actor_type,raw_text&order=turn_index.asc" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | jq
```

Expected:
- turns show alternating `USER` and `SYSTEM` actor types.
- rows are ordered by `turn_index` and remain append-only.

## 7) Commit contract (hard validation + exactly 10 docs + bundle)

```bash
COMMIT=$(curl -s "$SUPABASE_URL/functions/v1/commit-contract" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PROJECT_ID\",\"cycle_no\":$CYCLE_NO}")

echo "$COMMIT" | jq '{contract_version_id, contract_version_number, doc_count:(.documents|length), submission, reused_existing_version}'
CONTRACT_VERSION_ID=$(echo "$COMMIT" | jq -r '.contract_version_id')
```

Expected:
- `doc_count` is `10`.
- `contract_version_id` exists.
- `submission.path` is non-empty.

## 8) Verify submission record

```bash
curl -s "$SUPABASE_URL/rest/v1/submission_artifacts?contract_version_id=eq.$CONTRACT_VERSION_ID&select=id,project_id,cycle_no,contract_version_id,bucket,storage_path,submitted_at" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq
```

Expected:
- one row exists with matching `contract_version_id`.
- `storage_path` equals `submission.path` from commit response.

## 9) Operator retrieval

Operator download path is Supabase Dashboard -> Storage -> bucket `shipfirst-submissions` using `storage_path` from `submission_artifacts`.

Optional CLI check for recent submission objects (uses `PROJECT_REF`, never `.supabase/project-ref`):

```bash
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "set SUPABASE_ACCESS_TOKEN first (Dashboard -> Account -> Access Tokens)" >&2
else
  curl -s "https://api.supabase.com/v1/projects/$PROJECT_REF/storage/buckets/shipfirst-submissions/objects?limit=20" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" | jq
fi
```

## 10) Quick auth/RLS triage queries

If `Your Runs` fails, run:

```bash
curl -s "$SUPABASE_URL/rest/v1/projects?select=id,name,created_at&order=created_at.desc" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq

curl -s "$SUPABASE_URL/rest/v1/contract_versions?select=id,project_id,cycle_no,version_number,created_at&order=created_at.desc&limit=5" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq

curl -s "$SUPABASE_URL/rest/v1/submission_artifacts?select=id,contract_version_id,storage_path,submitted_at&order=submitted_at.desc&limit=5" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq
```

Expected:
- `projects` should return `[]` or rows, not auth errors.
- If `submission_artifacts` is 403 but others succeed, run listing still works (submissions are treated as optional metadata).
