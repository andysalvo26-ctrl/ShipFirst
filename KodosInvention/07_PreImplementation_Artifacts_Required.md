# Pre-Implementation Artifacts Required
Status: Binding

## Purpose
This document names the minimum artifacts that must be frozen before creating a new Kodos Xcode project. It prevents implementation from guessing policy, legality, and lifecycle semantics. It is the dependency list for safe execution.

## Binding Statements
- A Transition Contract Table is required: each typed action maps to legal mutation sets across `intake_turns`, `decision_items`, `interview_checkpoints`, `interview_turn_state`, and commit blockers.
- A Commit Readiness Contract is required: explicit blocker classes and pass criteria beyond single-key confirmation.
- An Artifact Verification Contract is required: ingestion status semantics, verification semantics, and legal transitions from unverified to verified/corrected.
- A Replay/Trace Contract is required: required identifiers and idempotency expectations across turn, checkpoint, and commit boundaries.
- A Canon Freeze Addendum is required: explicit list of authoritative docs for Kodos implementation and explicit non-authoritative legacy sources.

## Definitions
- Transition Contract Table: Canonical mapping from typed action category to permitted state changes.
- Commit Readiness Contract: Canonical gate rules defining when commit is legal.
- Canon Freeze Addendum: Explicit authority map used during implementation.

## Evidence Pointers
- `supabase/functions/next-turn/index.ts`
- `supabase/functions/commit-contract/index.ts`
- `supabase/functions/_shared/interview_gates.ts`
- `InterviewEngine/Handshake.md`
- `InterviewEngine/AllowedMoves.md`
- `CANON_PRECEDENCE.md`
- `scripts/verify_interview_engine_contract.sh`
