# Drift Map

This map links existing specs/code to the interview thinking framework and flags what should change vs remain.

| Source | Drift | Keep / Change | Why |
|---|---|---|---|
| `ShipFirstBrain/StateMachine.md` | Fixed linear stage pipeline as primary behavior model | **Change** (for interview engine scope) | Calibration data requires oscillating posture transitions (verify/extract/recover), not strict linear motion during conversation. |
| `ShipFirstBrain/QuestioningSystem.md` | Strong MCQ policy but lacks burden-state and answerability gate as first-class runtime controls | **Change** | Needs explicit burden-aware selection logic and PAUSE-style recovery semantics. |
| `ShipFirstBrain/Brain_Laws.md` | Trust laws strong, but terminology uses `ASSUMED` without explicit `HYPOTHESIZED` alias rule | **Change (terminology clarification)** | Prevent conceptual mismatch between framework and schema labels. |
| `ShipFirstBrain_Canonical/05_Edge_Functions_and_Server_Boundary.md` | Generation/submit boundaries well-defined, but turn-loop contract is not explicit for posture/move/burden | **Change** | Needed to keep interviewer behavior inspectable and debuggable. |
| `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift` | UI supports chat + options + commit, but no explicit representation of posture transitions | **Keep for now** | UI can remain largely stable while engine contract is hardened behind boundary. |
| `ShipFirstIntakeApp/ShipFirstIntakeApp/Models.swift` | Trust labels represented; decision state derived mostly from lock state | **Change (later, minimal)** | Needs explicit support for hypothesis confirmation linkage and artifact state metadata. |
| `supabase/functions/next-turn/index.ts` | Heuristic locking can silently promote inferred meaning | **Change (required before engine implementation)** | Violates trust boundary and no-silent-guessing principle. |
| `supabase/functions/generate-docs/index.ts` | Hard gates can fail early; stage naming assumes doc pipeline even during exploratory state | **Keep commit strict, adjust turn semantics later** | Conversation should stay open while commit remains strict; generation endpoint may remain downstream. |
| `supabase/migrations/20260210133000_canonical_brain_schema.sql` | Strong base contract, but no artifact/posture/burden representation | **Change (additive migration needed)** | Framework cannot be implemented safely without representing these states. |
| `scripts/verify_db_contract.sh` | Validates structure/RLS only, not behavior trust rules | **Change** | Add behavior-oriented assertions/checklist hooks to prevent silent assumption drift. |

## Danger Zones (Trust-Critical)
- Any code path that marks inferred claims as `USER_SAID` without explicit confirmation.
- Any turn selection logic that cannot explain why a checkpoint was asked.
- Any artifact-provided flow that asks directional decisions before comprehension proof.
