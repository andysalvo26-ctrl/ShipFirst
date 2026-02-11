# Canon Precedence (ShipFirst Phase 1 / v3 Pre-Implementation)

This file is the tie-breaker authority when canon sources conflict.

## Precedence Order
1. `CANON_PRECEDENCE.md` (this file)
2. `ShipFirstBrain_Canonical/*` for Phase 1 intake behavior and contracts
3. `InterviewEngine/*` for posture/move behavior where not in conflict
4. Runtime code/schema/scripts as evidence of what exists today (not intended-truth authority)
5. `ALIGNMENT_REPORT.md` as audit evidence/context
6. `ShipFirstPlatform/*` informational until fully populated and explicitly promoted
7. Legacy/archive folders are non-authoritative

## Interpretation Rule
If runtime behavior conflicts with intended truth in canonical docs, implementation must change runtime behavior to match intended truth unless a canon update is explicitly approved.

