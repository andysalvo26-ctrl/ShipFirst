# Open Questions and Phase Gates (Phase 1 Canonical)

## Why this exists
Open questions are not a weakness; they are the boundary between shipped truth and future scope. This document prevents accidental roadmap drift by separating unresolved decisions from active obligations. It keeps teams aligned on what must remain true before Phase 2 expansion.

## Open questions that can cause future drift
1. When to introduce an org-level tenant key beyond `owner_user_id`.
2. How to phase in customer runtime operations without weakening trust/provenance contracts.
3. What explicit reliability targets should govern generation and submit in production.
4. What retention policy should apply to intake, contract, and submission artifacts.
5. What formal approval model should govern break-glass operations.
6. What minimum CI posture is required before Phase 2 scope opens.
7. How operator workflows should evolve without creating an unbounded internal surface.

## Phase 1 gate set (must remain true)
- One active customer-facing intake surface.
- Exactly ten role docs required for run success.
- Trust labels and provenance pointers on all claims.
- User review of all ten docs before submit.
- Submit creates zip + manifest in private storage and records metadata.
- Supabase Auth + RLS enforce ownership boundaries.
- LLM calls remain server-side only.

## Phase 2 promise (non-binding)
Phase 2 is expected to extend owner-operated app control surfaces, but only after Phase 1 gates are stable and verifiably enforced in real usage.

## Drift trigger conditions
Any proposal that adds runtime console behavior, auto-build/deploy claims, or hidden inference paths before Phase 1 gates remain stable is out of scope and must be deferred.
