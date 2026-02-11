# ShipFirst Kodos v2 Implementation Notes

## What Was Reused
- Existing Supabase auth/session handling and API boundary from `ShipFirstKodosApp`.
- Existing backend contracts: `next-turn`, `commit-contract`, `submit-run`.
- Existing trust and invariant model from `Models.swift` (trust labels, confirmed-by-turn, exactly-10 validation).

## What Was Rebuilt
- New root project folder: `ShipFirstKodosV2App`.
- UI flow and state-mapping in `ShipFirstKodosV2App/ShipFirstIntakeApp/Views.swift` now prioritize one cognitive job per turn.
- Local readiness gate logic now requires both:
  - core decisions confirmed, and
  - enough plain-language setup signal before generation is offered.

## Critical UX Rules Enforced
- No backend jargon in primary UI.
- Website context is optional and first-step.
- Option selection can support two choices only for compatible capability steps.
- Commit path appears only when setup state is mature enough.
- Readiness-control options from backend are hidden until true local commit readiness is met.
- “Next step” question falls back to unresolved setup buckets, so users see plain setup prompts instead of process prompts.

## Run / Test
- Open: `ShipFirstKodosV2App/ShipFirstIntakeApp.xcodeproj`
- Scheme: `ShipFirstIntake`
- Destination tested: `iPhone 17 Pro (iOS 26.2)`

## Notes
- Backend schemas/endpoints were not changed in this pass.
- This pass is focused on v2 app-surface behavior and readiness equilibrium.
