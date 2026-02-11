# Posture Modes

The engine must run explicit interview posture modes.  
Without explicit mode control, questions drift into mixed cognitive jobs and trust degrades.

## Exploration
- Purpose: collect raw intent in user language.
- Enter when: idea is broad, ambiguous, or newly introduced.
- Allowed moves: open prompt, reflective summary, low-commitment clarification.
- Forbidden moves: implementation framing, feature-package forcing, compound forks.
- Exit when: there is enough signal to test an interpretation.

## Artifact Grounding
- Purpose: process and verify user-provided artifacts (website, brand pages, public assets).
- Enter when: user provides artifact reference or uploaded artifact.
- Allowed moves: comprehension summary with correction request.
- Forbidden moves: directional product-choice prompts before comprehension is confirmed.
- Exit when: user validates or corrects core interpretation.

## Verification
- Purpose: verify interpretation with minimal user effort.
- Enter when: engine has material hypotheses that affect direction.
- Allowed moves: yes/mostly/no, short correction prompts, single-claim validation.
- Forbidden moves: stacking unrelated validations in one prompt.
- Exit when: claim is confirmed, corrected, or explicitly left unresolved.

## Extraction
- Purpose: fill high-impact meaning gaps after trust is established.
- Enter when: verified context exists and unresolved build-critical unknowns remain.
- Allowed moves: targeted, answerable questions tied to confirmed context.
- Forbidden moves: broad abstraction that requires user to model an app internally.
- Exit when: next step requires explicit fork resolution or burden rises.

## Alignment Checkpoint
- Purpose: resolve a high-impact fork with constrained options.
- Enter when: continuing would require a silent assumption.
- Allowed moves: 2-5 choices, plus `none fit`, plus explicit custom path.
- Forbidden moves: presenting options as exhaustive truth.
- Exit when: fork is resolved or rejected.

## Recovery
- Purpose: reduce burden and restore answerability.
- Enter when: PAUSE-like feedback, confusion, repetitive “not sure,” or abrupt engagement drop.
- Allowed moves: simplify question, reduce abstraction, reset to one low-burden choice.
- Forbidden moves: argument, re-asking same overloaded prompt, hidden scope escalation.
- Exit when: user gives crisp answer or confirms readiness to continue.

## Transition Rule
Mode transitions require an explicit reason tied to one of:
- uncertainty level,
- trust verification need,
- burden spike,
- contradiction resolution need,
- artifact ingestion event.

## Artifact Priority Rule
After artifact ingestion, mode order is constrained:
1) Artifact Grounding
2) Verification
3) then Extraction or Checkpoint as justified

Directional decisions before artifact verification are out-of-policy.
