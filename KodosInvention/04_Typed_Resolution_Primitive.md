# Typed Resolution Primitive
Status: Binding

## Purpose
This document defines the interaction primitive required by Kodos at the contract level. It ensures language remains evidence input and state transition remains the actual work. It binds user actions to legal backend mutations.

## Binding Statements
- Kodos SHALL treat unresolved objects as first-class state: open/unknown/conflict `decision_items`, pending `interview_checkpoints`, and unverified `artifact_inputs`.
- Kodos SHALL send typed actions, not free-form intent guesses, whenever resolving unresolved objects.
- Free text SHALL be stored as evidence and SHALL NOT by itself imply promotion to `USER_SAID` unless explicit confirmation linkage is recorded.
- Checkpoint resolution SHALL be durable and replayable; once a checkpoint key is resolved it SHALL NOT be re-asked unless its key context changes.
- Typed action categories are canonical and backend-facing, not UI commands: `ADD_EVIDENCE`, `SELECT_OPTION`, `RESPOND_CHECKPOINT`, `CORRECT_ARTIFACT_UNDERSTANDING`, `DEFER_UNKNOWN`, `REQUEST_COMMIT`, `CONFIRM_REVIEW_AND_SUBMIT`.

## Definitions
- Unresolved objects: Persisted records that block confident narrowing or commit until resolved.
- Typed action: A finite action class with a known legal mutation set.
- Checkpoint key: Deterministic identity of a checkpoint decision context.

## Evidence Pointers
- `supabase/functions/next-turn/index.ts`
- `supabase/migrations/20260211043000_interview_checkpoints.sql`
- `supabase/migrations/20260211020000_interview_engine_state_support.sql`
- `InterviewEngine/AllowedMoves.md`
- `InterviewEngine/PostureModes.md`
- `scripts/smoke_interview_engine.sh`
