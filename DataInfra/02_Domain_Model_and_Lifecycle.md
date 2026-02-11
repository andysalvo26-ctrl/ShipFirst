# Domain Model and Lifecycle

## Purpose
- Define the minimum domain boundaries and table semantics required for scale, auditability, and deterministic behavior.
- Clarify event-vs-state modeling and mutable-vs-append-only rules.

## Non-goals
- No UI design decisions.
- No attempt to model post-launch customer app console domains in this phase.

## Decisions / Invariants
- Current core data domains:
  - Project and cycle context: `projects` (state anchor), `active_cycle_no`.
  - Intake evidence: `intake_turns` (append-only).
  - Alignment decisions: `decision_items` (mutable key-state per cycle with evidence refs + lock_state).
  - Generation execution trace: `generation_runs` (event log by stage).
  - Contract state snapshots: `contract_versions` + `contract_docs` + `requirements` + `provenance_links`.
  - Submission artifact state: `submission_artifacts` (storage object reference + manifest).
  - Audit trail: `audit_events` (cross-layer event log).
- Event vs state tables:
  - Event-style: `intake_turns`, `generation_runs`, `audit_events`.
  - State snapshots: `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `submission_artifacts`.
  - Mutable state: `projects`, `decision_items`.
- Append-only rules:
  - `intake_turns`: append-only; no update/delete.
  - `contract_versions`: immutable after commit.
  - `generation_runs` and `audit_events`: append-only operational events.
- Mutable rules:
  - `projects`: mutable metadata only, never ownership transfer without explicit governance action.
  - `decision_items`: upsert by `(project_id, cycle_no, decision_key)`; evidence refs cannot be empty.
- Storage artifact strategy:
  - `submission_artifacts.storage_path` is canonical handoff locator.
  - Bucket remains private.
  - Artifact manifest must include IDs/timestamps/doc metadata for replayability.
- Scale posture (pragmatic):
  - Keep single Postgres cluster posture now.
  - Index high-cardinality access paths already used by app/functions (project+cycle, version lookup, role lookup, artifact lookup).
  - Partitioning deferred until observed thresholds are hit (see open questions).

## Open questions
- Retention policy:
  - Keep all historical intake/events forever for audit, or archive old rows after N months into cold storage?
- Partition trigger thresholds:
  - At what row counts/latency percentiles do `intake_turns`, `generation_runs`, and `audit_events` move to partitioned strategy?
- Submission artifact retention:
  - Keep all bundles permanently, or move old artifacts to lower-cost archive tier with restore process?

## Next implementation steps
- Add a documented lifecycle matrix in repo (table, retention, mutability, archival target, deletion policy).
- Add SQL guard checks for mutability rules:
  - Trigger tests for append-only tables.
  - Constraint tests for exactly-10 docs and trust/provenance integrity.
- Add index review checkpoint every release:
  - Capture query stats for iOS list/detail, generate, submit.
  - Confirm index usefulness before adding new indexes.
- Define deletion/anonymization workflow for user data requests without breaking audit chain integrity.
