# Minimum Viable Kodos Acceptance
Status: Binding

## Purpose
This document defines the smallest runnable proof that Kodos works as the correct primitive over existing backend contracts. Acceptance is lifecycle and trust-contract based, not visual or stylistic. This is the minimum bar before broadening interaction complexity.

## Binding Statements
- A user can complete one run where evidence intake, checkpoint resolution, commit, review, and submit are all exercised against live backend contracts.
- Commit SHALL fail when blockers remain and SHALL succeed only when contract gates pass and exactly 10 docs are materialized.
- Submit SHALL occur only after commit and explicit review confirmation and SHALL produce recorded submission metadata.
- Artifact ingestion path SHALL demonstrate both success and failure handling without fake browsing claims.
- No step in happy path may require client-side provider secrets or bypass ownership checks.

## Definitions
- MV Kodos: First runnable implementation proving typed resolution and lifecycle correctness end-to-end.
- Acceptance criteria: Contract-level outcomes that must pass for go/no-go decisions.

## Evidence Pointers
- `scripts/smoke_interview_engine.sh`
- `scripts/verify_interview_engine_contract.sh`
- `scripts/verify_db_contract.sh`
- `ShipFirstIntakeApp/ShipFirstIntakeAppTests/RunValidationTests.swift`
- `ShipFirstIntakeApp/ShipFirstIntakeAppTests/SubmissionManifestTests.swift`
- `supabase/functions/next-turn/index.ts`
- `supabase/functions/commit-contract/index.ts`
- `supabase/functions/submit-run/index.ts`
