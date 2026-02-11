# Contracts Kodos Depends On
Status: Binding-Except-UNKNOWN

## Purpose
This document defines the minimum backend contracts Kodos depends on to operate without hidden inference. It marks what is already sufficient and what may require contract tightening before implementation. It is intentionally contract-focused and not UI-focused.

## Binding Statements
- Kodos primary interaction endpoint is `POST /functions/v1/next-turn`.
- Kodos lifecycle endpoints are `POST /functions/v1/commit-contract` and `POST /functions/v1/submit-run`, with commit and submit remaining separate operations.
- `next-turn` response contract SHALL include `posture_mode`, `move_type`, `unresolved`, `can_commit`, `commit_blockers`, and `trace`.
- If artifact verification is pending, `next-turn` SHALL return checkpoint state and SHALL not silently proceed as verified.
- Authentication for all function calls SHALL use user JWT bearer token plus anon key; provider/service secrets remain server-side only.

## Definitions
- Contract dependency: A request/response or data guarantee Kodos requires from backend to function correctly.
- Commit blockers: Structured reasons commit is not currently legal.
- Trace: Correlation metadata sufficient for replay/debug linkage.

## Evidence Pointers
- `supabase/functions/next-turn/index.ts`
- `supabase/functions/commit-contract/index.ts`
- `supabase/functions/submit-run/index.ts`
- `ShipFirstIntakeApp/ShipFirstIntakeApp/Models.swift`
- `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`
- `supabase/migrations/20260210133000_canonical_brain_schema.sql`
- `supabase/migrations/20260211032000_v3_website_ingestion_state.sql`

## UNKNOWN
- Whether current `next-turn` trace payload is sufficient for long-term replay analysis across all typed actions. Resolution evidence: agreed replay contract in canonical docs and matching verifier checks.
