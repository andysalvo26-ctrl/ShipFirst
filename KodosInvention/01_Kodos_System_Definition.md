# Kodos System Definition
Status: Binding

## Purpose
This document defines what Kodos is in system terms so implementation decisions do not drift into new product scope. It constrains Kodos to being a surface for the existing epistemic machine. It separates lifecycle truth from interaction details.

## Binding Statements
- Kodos SHALL use `next-turn` as the interaction boundary for evidence intake and typed resolution events.
- Kodos SHALL treat backend state as authoritative for unresolved objects, commit blockers, and readiness.
- Kodos SHALL call `commit-contract` to materialize contract state and SHALL call `submit-run` only as an explicit post-review action.
- Kodos SHALL NOT introduce alternate truth stores for decisions, checkpoints, or artifact verification.
- Kodos SHALL preserve project-scoped ownership and RLS assumptions already enforced in Supabase.

## Definitions
- Epistemic machine: The backend state system that stores evidence, hypotheses, unknowns, confirmations, and commit gates.
- Commit: Truth-gate operation that validates and writes immutable exactly-10 contract state.
- Submit: Separate handoff operation that creates bundle/manifest artifacts in storage.

## Evidence Pointers
- `supabase/functions/next-turn/index.ts`
- `supabase/functions/commit-contract/index.ts`
- `supabase/functions/submit-run/index.ts`
- `supabase/migrations/20260210133000_canonical_brain_schema.sql`
- `supabase/migrations/20260210213000_phase1_launch_hardening.sql`
- `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`
