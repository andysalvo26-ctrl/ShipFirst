# Supabase Alignment

## Current Schema Findings Relevant to Interview State

### Represented Today
- `intake_turns` provides append-only turn history with actor tags.
- `decision_items` provides trust labels (`USER_SAID` / `ASSUMED` / `UNKNOWN`) and lock state.
- `decision_state`, `has_conflict`, and `conflict_key` exist (chat loop migration).
- `generation_runs`, `audit_events` provide server trace logs.
- Provenance graph exists for committed packet (`requirements`, `provenance_links`).

### Missing or Weakly Represented
- No first-class artifact input record (website/source reference + ingestion quality + verification state).
- No first-class posture mode per turn.
- No first-class burden signal per turn.
- No explicit promotion linkage from hypothesis to confirmation event.
- No durable contradiction lifecycle (opened/resolved evidence trail), only boolean/key markers.

## Proposed Minimal Schema Delta (Not Applied in This Run)

The following is the minimum additive delta to support the engine framework cleanly without overengineering:

1) `public.artifact_inputs` (new, project-scoped)
- Purpose: capture artifact references and comprehension verification state.
- Minimum fields:
  - `id`
  - `project_id`
  - `cycle_no`
  - `artifact_type` (website, brand_page, uploaded_doc, other)
  - `artifact_ref` (url/path/reference)
  - `ingest_state` (pending, partial, complete, failed)
  - `summary_text`
  - `verification_state` (unverified, user_confirmed, user_corrected)
  - `created_at`, `updated_at`

2) `public.interview_turn_state` (new, project-scoped)
- Purpose: per-turn posture/control snapshot for replay and debugging.
- Minimum fields:
  - `id`
  - `project_id`
  - `cycle_no`
  - `turn_id` (ref `intake_turns.id`)
  - `posture_mode`
  - `move_type`
  - `burden_signal` (low, medium, high)
  - `pace_signal` (opening, narrowing, reopening)
  - `transition_reason`
  - `created_at`

3) `public.decision_items` (additive columns)
- `confirmed_by_turn_id` (nullable ref to `intake_turns.id`)
- `hypothesis_rationale` (nullable text)
- Purpose: prevent silent promotion and preserve why an item is `ASSUMED/HYPOTHESIZED`.

4) `public.decision_conflicts` (optional new table, preferred over bool-only)
- If added, keep minimal:
  - `id`, `project_id`, `cycle_no`, `conflict_key`, `status`, `opened_by_turn_id`, `resolved_by_turn_id`, `created_at`, `resolved_at`
- Purpose: track contradiction lifecycle explicitly.

## RLS Considerations
- Every new table must include `project_id` and enforce `user_owns_project(project_id)`.
- Client writes should remain constrained:
  - client may insert artifact references,
  - server updates ingestion/verification outcomes.
- Interview state snapshots should be server-written; client select-only.
- Decision promotion metadata updates should require ownership and confirmation provenance in payload validation.

## Why This Delta Is Minimal
- Reuses existing ownership model and project/cycle keys.
- Avoids org/tenant redesign.
- Adds only state required to enforce posture, trust, and artifact-grounding behavior seen in calibration data.
