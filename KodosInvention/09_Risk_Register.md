# Kodos Risk Register
Status: Binding

## Purpose
This document captures the top trust-critical risks for Kodos implementation and the required guardrail for each. It is limited to real risks evidenced in the current repo and contracts. It is a control artifact, not a roadmap.

## Binding Statements
- Every listed risk SHALL have a guardrail tied to an enforceable contract, verifier, or schema constraint.
- Risks that can silently distort intent are severity-critical and SHALL be blocked before release.
- Guardrails SHALL favor replayability and explicit state over heuristic behavior.

## Definitions
- Silent promotion: Inferred meaning becoming `USER_SAID` without explicit confirmation linkage.
- Lifecycle collapse: Commit and submit semantics merging into one side-effectful action.
- Drift: Divergence between canonical intended behavior and executable runtime behavior.

## Binding Risk Entries
- Risk: Silent promotion of inferred claims.
  Guardrail: Require `confirmed_by_turn_id` for `USER_SAID` confirmation predicates and verify in behavior gates.
- Risk: Repeated verification loops after resolution.
  Guardrail: Deterministic checkpoint key + durable checkpoint status with non-repetition unless key context changes.
- Risk: Commit/submit boundary regression.
  Guardrail: `commit-contract` must not write submission artifacts; `submit-run` remains explicit bundle writer.
- Risk: Artifact honesty drift.
  Guardrail: Website-derived claims require stored extract provenance and explicit ingest/verification state.
- Risk: Canon authority confusion during rebuild.
  Guardrail: Enforce precedence from `CANON_PRECEDENCE.md` and quarantine conflicting legacy authority claims.

## Evidence Pointers
- `supabase/functions/_shared/interview_gates.ts`
- `supabase/functions/next-turn/index.ts`
- `supabase/functions/commit-contract/index.ts`
- `supabase/functions/submit-run/index.ts`
- `supabase/migrations/20260211043000_interview_checkpoints.sql`
- `supabase/migrations/20260211032000_v3_website_ingestion_state.sql`
- `CANON_PRECEDENCE.md`
- `scripts/verify_interview_engine_contract.sh`
