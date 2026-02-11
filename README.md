# ShipFirst v0 Intake App

This repository implements one customer-facing intake surface and a minimal server boundary:
- iOS app: intake -> alignment checkpoints -> generate exactly 10 role docs -> review -> submit
- Edge Functions: `generate-docs`, `submit-run`
- Submit uploads a zip bundle + manifest to private Storage bucket `shipfirst-submissions`

Canonical run identity is `(project_id, cycle_no)` and not `runs.id`.

## Configure Edge Function secrets

1. Open `supabase/functions/.env` and set:
   - `OPENAI_API_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `SHIPFIRST_BRAIN_VERSION`
2. Push secrets:

```bash
supabase secrets set --env-file supabase/functions/.env
```

These secrets are server-side only and must never be embedded in iOS code.

## Deploy database + functions

```bash
PROJECT_REF="${PROJECT_REF:-$(grep -E '^SUPABASE_URL' Config/Supabase.xcconfig | head -n1 | cut -d= -f2- | tr -d '[:space:]' | sed 's#:\$()/#://#' | sed -E 's#^https://([^.]+)\.supabase\.co/?$#\1#')}"
supabase link --project-ref "$PROJECT_REF"
supabase db push
supabase functions deploy generate-docs
supabase functions deploy submit-run
```

## Build and test iOS app

```bash
xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  build

xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  test
```

At runtime the app loads:
- `SHIPFIRST_SUPABASE_URL` from `Info.plist` (`$(SUPABASE_URL)` build setting)
- `SHIPFIRST_SUPABASE_ANON_KEY` from `Info.plist` (`$(SUPABASE_ANON_KEY)` build setting)

## End-to-end API verification

Use `VERIFY.md` for exact commands to:
- sign in
- create a project
- append intake turns
- call `generate-docs` and confirm 10 docs
- call `submit-run` and confirm `submission_artifacts.storage_path`

## Supabase tables used by this build

- Client writable: `projects`, `intake_turns`, `decision_items`
- Server writable (functions only): `generation_runs`, `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `submission_artifacts`, `audit_events`
- Storage bucket: `shipfirst-submissions` (private)
