# Edge Function Contract Alignment

## Current Boundaries (Observed)
- `next-turn` handles user turn ingestion, lightweight decision updates, and next question generation.
- `generate-docs` runs multi-stage gate checks and creates/reuses contract versions.
- `commit-contract` performs commit-time validation, creates version/docs/requirements/provenance, and creates submission artifact.
- `submit-run` creates zip+manifest and records submission metadata for latest committed version.

## Current Contract Gaps vs Engine Framework
- `next-turn` does not return explicit posture mode/move type.
- `next-turn` does not carry artifact ingestion or verification state.
- Burden/overload state is not represented in request/response.
- Promotion of inferred business type to locked `USER_SAID` can happen without explicit confirm event.
- Structured contradiction lifecycle is not surfaced in turn contract.

## Proposed Handshake Contract (Conceptual, Minimal)

### Turn Endpoint (conversation loop)
Request should include:
- `project_id`, `cycle_no`
- one user action: `user_message` or `selected_option_id`
- optional `artifact_ref` linkage (when present)
- optional `client_trace_id`

Response should include:
- `assistant_message`
- optional `options[]`
- `posture_mode`
- `move_type`
- `unresolved[]` (unknown/conflict pointers)
- `can_commit` + `commit_blockers`
- `trace` (`correlation_id`, `turn_id`, `decision_refs`)

### Commit Endpoint
- Must remain strict gate boundary.
- Must fail with structured issues if unresolved critical contradictions or non-confirmed high-impact hypotheses remain.
- Must not mutate decision truth state to pass commit.

## Idempotency and Replay Requirements
- Turn processing should be idempotent by `(project_id, cycle_no, turn_identity)`.
- Commit should remain idempotent by fingerprint + version key.
- All engine-significant transitions must be replayable from persisted logs/state snapshots.

## Security Contract (Unchanged)
- Client uses anon key + bearer JWT only.
- Service role remains server-only.
- Ownership checks must run before project-scoped writes.
