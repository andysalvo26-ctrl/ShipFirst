ShipFirstBrain Draft v0 Audit

Scope of this audit:
- Baseline is the pasted Draft v0 files.
- Goal is to keep the Brain as interviewer plus 10-doc contract generator only.
- This audit identifies drift, gaps, contradictions, and template risk before canonical rewrite.

Drift check (interviewer vs app builder)
- Drift risk: some language in README and handshake can be read as a general product control plane rather than a narrow interviewer pipeline.
- Drift risk: Build Plan and Acceptance Tests role descriptions can accidentally imply runtime solution design if not constrained to contract content only.
- Drift risk: references to deployment, release, or runtime in non-brain files may pull scope into implementation planning.
- Drift risk: retrieval and embeddings sections can be interpreted as product memory beyond interview context unless explicitly scoped to intake/contract quality.

Gaps (builder would have to guess)
- Stage input/output names are present but not fully normalized across files; a builder could guess wrong on artifact handoffs.
- Confirmation gate criteria are not quantified enough; blocking vs non-blocking unknown handling needs one explicit policy.
- Word budgets exist but hard max and soft target enforcement model is not consistently specified per role.
- MCQ policy lacks a single canonical option shape and escalation path when user says none fit.
- Contradiction severity model appears in multiple files but without one source of truth mapping severity to gate behavior.
- Replay expectations are stated but acceptable variance is not tied to a concrete validation profile.
- Embedding fallback exists but stage-by-stage behavior when retrieval is unavailable is under-specified.
- Commit semantics need one explicit statement of atomicity and idempotency interaction.

Contradictions detected
- Evidence strictness appears with mixed defaults: one place implies strict dual-link evidence, another allows softer fallback without role-critical distinction.
- Replay strictness appears in multiple forms; structural replay is preferred, but language around divergence thresholds is not centralized.
- Transition criteria between Ambiguity and Confirmation vs Confirmation and Assembly are described differently across files.
- Contradiction blocking policy is both class-based and potentially user-controlled in different places.

Template risk (carbon-copy outputs)
- Stable spine is strong, but there is no explicit anti-repetition check tied to validation severity.
- Adaptive modules are defined, but selection policy can become static and produce repetitive packets.
- Client language palette is mentioned but not tied to measurable constraints (for example lexical overlap thresholds).
- Builder Notes could become formulaic unless purpose constraints are explicit.

Suggested edits applied in canonical rewrite
- Normalize all core artifact names and stage outputs across StateMachine and RecordModel.
- Define one canonical gate matrix mapping issue type and contradiction severity to block/warn outcomes.
- Add explicit word-budget model for each role: soft target plus hard max and hard minimum.
- Add one MCQ policy with option shape, none-fit branch, custom path, and fatigue thresholds.
- Add explicit UNKNOWN survival rule from intake to docs and validation check to prevent silent certainty upgrades.
- Add stage-specific retrieval behavior and fallback behavior for embeddings outage.
- Add explicit commit semantics: atomic commit, idempotent key, no partial state.
- Add anti-template mechanism as enforceable checks (repetition and genericness warnings).

Self-Audit (One Loop)

Checklist results:
- Exactly 10 doc role IDs, unchanged, present, with budgets and Builder Notes rules: PASS
- Every Requirement and Decision concept includes status plus evidence_refs rule: PASS
- State machine transitions plus stop and rollback plus commit semantics are clear: PASS
- RecordModel entities cover everything used by stages: PASS
- Validation rules clearly define block vs warn: PASS
- Creativity mechanism is concrete and prevents carbon-copy outputs: PASS
- Embeddings plan is actionable and has fallback behavior: PASS
- ImplementationHandshake describes operations plus idempotency plus commit: PASS
- No place implies brain builds the app: PASS

Loop note:
- One self-audit loop completed.
- Two fixes were applied after re-read: explicit derived Unknown and Assumption views in RecordModel, and explicit non-app-builder wording in BUILD_PLAN role.
