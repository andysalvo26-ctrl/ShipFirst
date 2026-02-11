# Handshake (Engine Boundary)

This is the minimal contract between client/orchestration layers and the interview engine.  
It defines behavior state exchange only, not UI structure.

## Engine Input Contract (Conceptual)
Each turn request must carry:
- `project_id`
- `cycle_no`
- `actor_turn` (user text or constrained selection)
- `turn_context` (prior turn refs and optional replay token)
- optional `artifact_ref` set (when website/docs are introduced)

Optional but recommended:
- `client_trace_id`
- `selected_option_id`
- `none_fit_text`

## Engine Output Contract (Conceptual)
Each response must return:
- `assistant_message`
- optional `options[]` (if checkpoint move)
- `posture_mode` used for this response
- `unresolved_items` (at least unknown/conflict refs)
- `commit_readiness` (boolean + blockers)
- `trace` metadata (correlation/run identity)

## Logging for Replay and Debugging
Every turn should log:
- input refs (not raw secrets),
- chosen move,
- posture transition reason,
- certainty-layer changes (`USER_SAID` / `HYPOTHESIZED|ASSUMED` / `UNKNOWN`),
- burden signal at turn end,
- artifact verification state if artifacts present.

## Determinism and Idempotency Expectations
- Replayed identical turn payload with same context token should not create duplicate semantic state.
- Side effects should be idempotent by `(project_id, cycle_no, turn_identity)`.
- Hypothesis promotion requires explicit confirmation event linkage.

## Minimal State Representation Required
The system must be able to represent, at minimum:
- current posture mode,
- active unresolved unknowns,
- hypothesis list pending confirmation,
- confirmed user-stated claims,
- contradiction markers,
- burden signal and last recovery event,
- artifact verification status.

If these states are not representable, the engine cannot reliably control pace or trust boundaries.
