# ShipFirst Platform Definition (Phase 1 Canonical)

## Why this exists
This document defines what ShipFirst is shipping now so teams can build and operate from one source of truth. Phase 1 is not the final product vision, but it is the trust substrate that future owner-operated apps depend on. It captures meaning, ownership, and governance in a way that is testable today. It intentionally avoids pretending that runtime app operations are already in scope.

## Phase 1 truth
ShipFirst Phase 1 is one customer-facing intake surface that runs this loop: intake, alignment checkpoints, exactly-10 document generation, review, and submission bundle handoff. A run is successful only when all ten role documents exist and pass server-side validation. The current release is meant to preserve meaning and auditability, not to automate app implementation or runtime operations.

## In scope now
- One customer-facing Intake Surface in iOS.
- Server-side generation and submit boundary via Supabase Edge Functions.
- Supabase Auth + RLS as ownership enforcement.
- Exactly-10 document contract with role IDs 1..10.
- Trust labels and provenance pointers on every claim.
- Submission bundle (`zip + manifest`) uploaded to private storage and recorded.

## Out of scope now
- Runtime owner console for operating live apps.
- Multi-surface customer suite beyond intake.
- Automatic "10 docs to app" generation or deployment.
- New tenant models beyond Phase 1 ownership root.

## Core terms
- `Run`: one intake session represented by `(project_id, cycle_no)`.
- `Contract Packet`: the ten interlocking documents produced for a run.
- `Claim`: a requirement-level statement inside a contract document.
- `Trust Label`: `USER_SAID`, `ASSUMED`, or `UNKNOWN`.
- `Provenance Pointer`: source reference to intake turn(s) or decision event(s).
- `Submission Bundle`: final zip artifact plus manifest uploaded on submit.

## Enforceable invariants
1. Exactly 10 role docs (1..10) are required for success.
2. Unknown meaning remains `UNKNOWN` until explicit user confirmation.
3. Every claim carries trust label plus provenance pointer(s).
4. Users can review all ten documents before final submission.
5. Client never carries provider secrets; LLM calls stay server-side.
6. Auth and RLS enforce per-user ownership boundaries.

## Future direction (non-binding)
Phase 2 is expected to introduce owner-operated app surfaces, but only after Phase 1 contracts are stable in production and verification gates consistently pass.
