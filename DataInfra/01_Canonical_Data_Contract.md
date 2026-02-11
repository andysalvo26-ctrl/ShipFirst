# Canonical Data Contract

## Purpose
- Establish one authoritative contract for schema, RLS, and cross-layer data assumptions across iOS, Edge Functions, and Postgres.
- Eliminate reactive production patches by making drift detectable before runtime.

## Non-goals
- This document does not redesign product behavior.
- This document does not add new data domains beyond current intake -> 10-doc -> submit flow.

## Decisions / Invariants
- Canonical schema source of truth is `supabase/migrations/20260210133000_canonical_brain_schema.sql`, with later additive migrations only.
- Runtime contract for a run is `(project_id, cycle_no)`; no `runs` table.
- Mandatory invariants for current scope:
  - Exactly 10 docs per committed contract version (`role_id` 1..10).
  - Every requirement includes trust label (`USER_SAID`, `ASSUMED`, `UNKNOWN`) and provenance links.
  - Client writes only: `projects`, `intake_turns`, `decision_items`.
  - Server writes only: `generation_runs`, `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `submission_artifacts`, `audit_events`.
- Drift-prevention rule:
  - Any new client or function query must be listed in a machine-checkable contract file before merge.
  - CI must verify queried columns exist in migrated schema.
- Versioning rule:
  - Schema version is migration history.
  - API/data contract version is tracked in `SHIPFIRST_BRAIN_VERSION` and documented release notes.
  - Contract versions in DB are immutable snapshots; new meaning requires new version row.

## Open questions
- Should ownership be denormalized as `owner_user_id` on all project-scoped tables for simpler RLS and easier debugging, or remain join-based through `projects`?
- Should schema contract checks run in CI via ephemeral DB boot + introspection query, or static parsing of SQL migrations plus known query manifests?
- Should there be a generated artifact (`DataInfra/schema_contract.json`) listing required tables/columns/policies for automated drift checks?

## Next implementation steps
- Create `DataInfra/schema_query_manifest.md` (or JSON) listing current live queries by component:
  - iOS `Services.swift` table/column use.
  - Edge function expected writes/reads.
- Add CI step:
  - Spin up disposable DB from migrations.
  - Run SQL assertions that all manifest columns exist.
- Add CI gate:
  - Fail if a PR changes schema-relevant client/function queries without updating manifest + docs.
- Add migration policy:
  - No edits to historical migrations after deployed.
  - All hotfixes are additive idempotent migrations with verification SQL.
