# Runtime Observability and Verification

## Purpose
- Make production failures diagnosable in minutes, not days, across iOS, Edge, Postgres, and Storage.
- Standardize deterministic smoke checks that catch schema/RLS/auth drift before users hit it.

## Non-goals
- No vendor lock-in to a full external observability stack in this phase.
- No large incident-management platform rollout right now.

## Decisions / Invariants
- Correlated tracing fields must be present in every critical flow:
  - `project_id`, `cycle_no`, `contract_version_id` (when present), `submission_id` (when present), request timestamp, actor (`user`/`service`).
- iOS diagnostics requirements:
  - Log session presence, user id, token expiry metadata, and operation name.
  - Distinguish `401 unauthorized` from `403 forbidden` from schema-level `400` errors.
- Edge diagnostics requirements:
  - Log stage start/fail/pass for generation pipeline.
  - Log ownership checks and storage upload outcomes.
  - Never log secrets or full tokens.
- DB diagnostics requirements:
  - `audit_events` entries for committed contract versions and submission uploads.
  - Queryable evidence that each submit maps to an exact contract version and storage path.
- Verification must be reproducible:
  - One command sequence validates sign-in, project creation, intake append, decision upsert, generation of 10 docs, submit bundle, and artifact retrieval.
- Drift checks are first-class:
  - Schema and policy introspection queries run before app smoke tests.

## Open questions
- Should edge function logs include deterministic `run_identity` in every response for easier support triage?
- Should verification be split into:
  - pre-deploy DB contract checks
  - post-deploy runtime smoke checks
  - nightly synthetic transaction?
- Should submission bundle hash verification be automated as a post-submit integrity check?

## Next implementation steps
- Add `VERIFY_DB_CONTRACT.sql` with checks for:
  - required columns on all in-scope tables
  - RLS enabled on all in-scope tables
  - expected policies exist and reference valid columns.
- Add `VERIFY_RUNTIME.md` script section:
  - iOS console log markers expected per step.
  - Curl checks for `projects`, `contract_versions`, `submission_artifacts`, `generate-docs`, `submit-run`.
- Add edge response envelope convention:
  - include correlation fields in success and failure payloads where safe.
- Add failure playbook table to `VERIFY.md`:
  - symptom -> likely layer -> one query/command to confirm.
