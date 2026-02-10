# ShipFirst v0 Intake App

This repo contains one customer-facing iOS intake surface and a minimal Supabase server boundary:
- iOS app: intake -> alignment -> generate exactly 10 docs -> review -> submit
- Edge functions: `generate-docs`, `submit-run`
- Submit uploads a zip bundle + manifest to private bucket `shipfirst-submissions`

## 1) Configure secrets (Edge Functions only)

1. Open `supabase/functions/.env` and set values:
   - `OPENAI_API_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `SHIPFIRST_BRAIN_VERSION`
2. Push secrets:

```bash
supabase secrets set --env-file supabase/functions/.env
```

## 2) Supabase deploy steps

```bash
# from repo root
supabase link --project-ref irwiyqwxmsohhrnkawuf
supabase db push
supabase functions deploy generate-docs
supabase functions deploy submit-run
```

## 3) iOS build commands

```bash
# iOS device-style build (code signing disabled)
xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

# simulator build (code signing disabled)
xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# compile tests without running them
xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Notes:
- Running tests (`xcodebuild test`) requires a concrete simulator device.
- If CoreSimulator is unavailable on your machine, use the `build-for-testing` command above to verify test compilation.

## 3.1) Brain invariant unit tests (server-side helpers)

```bash
deno test supabase/functions/_shared/brain_contract_test.ts
```

## 4) End-to-end API test (generate + submit)

Set env vars first:

```bash
export SUPABASE_URL="https://irwiyqwxmsohhrnkawuf.supabase.co"
export SUPABASE_ANON_KEY="sb_publishable_3wEdpkCICEsGggVn1bUUFw_N-glz6gS"
export TEST_EMAIL="you@example.com"
export TEST_PASSWORD="change-me-123456"
```

Get an access token (create user first if needed):

```bash
# optional sign-up (ignore if user already exists)
curl -s "$SUPABASE_URL/auth/v1/signup" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" >/dev/null

ACCESS_TOKEN=$(curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" | jq -r '.access_token')

echo "$ACCESS_TOKEN" | head -c 24; echo
```

Create a run and add one intake turn:

```bash
RUN_ID=$(curl -s "$SUPABASE_URL/rest/v1/runs?select=id" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"status":"draft","current_stage":"DISCOVERY"}' | jq -r '.[0].id')

curl -s "$SUPABASE_URL/rest/v1/intake_turns?select=id" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "{\"run_id\":\"$RUN_ID\",\"turn_index\":1,\"actor_type\":\"USER\",\"raw_text\":\"I want a reading-focused learning app with weekly lesson cadence and clear progress checks.\"}" >/dev/null
```

Generate docs (must return 10 roles):

```bash
curl -s "$SUPABASE_URL/functions/v1/generate-docs" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"run_id\":\"$RUN_ID\"}" | jq '{contract_version_id, doc_count:(.documents|length)}'
```

Submit run (creates bundle zip in Storage):

```bash
curl -s "$SUPABASE_URL/functions/v1/submit-run" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"run_id\":\"$RUN_ID\"}" | jq
```

Verify submission record and storage path:

```bash
curl -s "$SUPABASE_URL/rest/v1/submissions?run_id=eq.$RUN_ID&select=id,contract_version_id,path,bucket,created_at" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq
```

The operator handoff artifact is the uploaded zip at `shipfirst-submissions/<user_id>/<run_id>/...` and can be downloaded from Supabase Dashboard -> Storage.
