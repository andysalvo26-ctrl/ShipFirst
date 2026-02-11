# Repo Alignment Report

## Executive Summary
Verdict: **PARTIALLY ALIGNED (NOT SAFE TO IMPLEMENT ENGINE YET)**.

The repo has strong foundations for trust labels, provenance links, RLS ownership, and commit-time exactly-10 enforcement.  
It is not yet aligned to the required interview-thinking framework because posture control, burden control, artifact-first verification, and explicit hypothesis-promotion mechanics are not represented as first-class state.  
Current behavior risks silent assumption promotion and premature narrowing even when the UI appears conversationally smooth.

## Top 10 Drift Risks
1. **Silent promotion risk in next-turn logic**: heuristic business type detection writes `USER_SAID` + `locked` without explicit confirmation.  
   File: `supabase/functions/next-turn/index.ts`

2. **No first-class posture mode state**: mode transitions are implicit in code branches and not persisted/replayable.  
   Files: `supabase/functions/next-turn/index.ts`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`

3. **No burden state representation**: no durable signal for overload/PAUSE-like recovery behavior.  
   Files: `supabase/functions/next-turn/index.ts`, `supabase/migrations/20260210133000_canonical_brain_schema.sql`

4. **Artifact ingestion not first-class**: no artifact references, ingestion status, or comprehension-verification record exists.  
   Files: `supabase/migrations/20260210133000_canonical_brain_schema.sql`, `supabase/functions/next-turn/index.ts`

5. **Trust taxonomy naming mismatch**: framework target uses `HYPOTHESIZED`, repo contracts use `ASSUMED` with no explicit alias rule in active platform docs.  
   Files: `supabase/functions/_shared/roles.ts`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Models.swift`

6. **Checkpoint eligibility not explicit**: constrained prompts are emitted heuristically, without logged “why-now” policy checks tied to answerability/burden.  
   File: `supabase/functions/next-turn/index.ts`

7. **Contradiction handling is minimal marker-only**: `has_conflict/conflict_key` exist, but conflict lifecycle and resolution evidence are not represented.  
   Files: `supabase/migrations/20260211003000_phase1_chat_loop_state.sql`, `supabase/functions/commit-contract/index.ts`

8. **Readiness narrowness risk**: `can_commit` in next-turn is keyed mainly to `business_type` confirmation; high-impact unknown coverage is not modeled.  
   File: `supabase/functions/next-turn/index.ts`

9. **Spec drift between interview framework and frozen brain docs**: existing `ShipFirstBrain/StateMachine.md` is a fixed linear pipeline, while calibration evidence demands oscillating posture transitions.  
   File: `ShipFirstBrain/StateMachine.md`

10. **Verification drift gap**: DB verifier checks structural columns/policies but not interview-law behavior (no silent promotion, burden recovery, artifact verification ordering).  
    Files: `scripts/verify_db_contract.sh`, `VERIFY.md`

## Already Aligned (Do Not Change)
- Project ownership root via `projects.owner_user_id` and `user_owns_project(project_id)` enforcement.
- RLS enabled on customer-path control-plane tables.
- Append-only intake turn intent (`intake_turns`).
- Exactly 10 role docs enforced at commit packet level.
- Server-side only model/provider calls and private submission bundle flow.

## Minimal Corrections Required Before Safe Engine Implementation
1. Add explicit representational contract for posture mode, burden signal, and transition reason per turn.
2. Add explicit artifact reference + verification state representation.
3. Add explicit hypothesis-promotion linkage (`confirmed_by_turn_id`/equivalent) to prevent silent truth promotion.
4. Align trust taxonomy language (`HYPOTHESIZED` alias to current `ASSUMED`) in canonical docs and handshake.
5. Extend verification rules to include behavioral contract checks (not only schema/RLS existence).
