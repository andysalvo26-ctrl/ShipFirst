# Control Plane Data Model (Phase 1)

## Canonical entities
- `projects`: tenant-owned container for intake and contract lifecycle.
- `intake_turns`: append-only user/system turns per `(project_id, cycle_no)`.
- `decision_items`: explicit meaning claims with status (`USER_SAID`/`ASSUMED`/`UNKNOWN`) and evidence refs.
- `generation_runs`: stage-level execution events for generation workflow.
- `contract_versions`: immutable committed snapshots.
- `contract_docs`: role-scoped documents (`role_id` 1..10) tied to a contract version.
- `requirements`: claim-level records with trust labels.
- `provenance_links`: requirement-to-source pointers.
- `submission_artifacts`: canonical storage handoff metadata.
- `audit_events`: security and operational audit trail.

## State vs event model
- Event-style append-only:
  - `intake_turns`, `generation_runs`, `audit_events`.
- Mutable phase-1 state:
  - `projects`, `decision_items`.
- Immutable snapshot set:
  - `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `submission_artifacts`.

## Invariants
1. `intake_turns` is append-only (update/delete blocked by trigger).
2. `contract_versions` is immutable after commit (update/delete blocked by trigger).
3. `decision_items` has canonical fields:
   - `decision_key`, `claim`, `status`, `evidence_refs`, `lock_state`, `updated_at`.
4. `contract_versions.version_number` exists and is deterministic per `(project_id, cycle_no)`.
5. Submission bundle references exact `contract_version_id` and storage path.

## Exactly-10 contract
- `contract_versions.document_count = 10` is enforced.
- `contract_docs.role_id` is constrained to `1..10`.
- Generate/submit functions re-validate role set completeness before success.

## Current backend boundary
- Implemented on Supabase Postgres + RLS + Edge Functions + Storage + Auth.
- No additional data stores are required for Phase 1.
