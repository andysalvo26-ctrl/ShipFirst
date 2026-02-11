# Control-Plane Data Model (Phase 1 Canonical)

## Why this exists
Phase 1 must preserve meaning over time, not just generate text once. This model defines the minimum records needed to prove what the user said, what was inferred, and what was finalized. It keeps the system durable for future owner-operated app operations without pretending those operations ship now.

## Record groups
- Intent capture: `intake_turns` (append-only turns).
- Meaning decisions: `decision_items` (`USER_SAID` / `ASSUMED` / `UNKNOWN`).
- Generation trace: `generation_runs` (stage events).
- Contract snapshots: `contract_versions`, `contract_docs`.
- Claim/provenance graph: `requirements`, `provenance_links`.
- Submission handoff: `submission_artifacts`.
- Security/ops history: `audit_events`.

## Mutability rules
- Append-only: `intake_turns`, `generation_runs`, `audit_events`.
- Mutable during active run: `projects`, `decision_items`.
- Immutable after commit: `contract_versions` and submitted contract artifacts.

## Contract packet invariants
1. Exactly ten docs per successful run.
2. Role IDs are fixed: `1..10`.
3. Every claim has trust label and provenance.
4. Unknown claims remain unknown unless explicitly confirmed.

## Phase 1 data boundary
This model does not include runtime app telemetry, live app settings, or deployment orchestration data. Those belong to later owner-operation phases and should not leak into this schema now.
