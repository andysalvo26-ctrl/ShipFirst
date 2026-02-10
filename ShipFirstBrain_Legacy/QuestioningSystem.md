Questioning System

Objective:
- Maximize information gain per user effort.
- Preserve trust labels and provenance.
- Move from open discovery to constrained confirmations without forcing false certainty.

Question modes:
1. Freeform Discovery
- Broad prompts for intent, constraints, tone, and edge cases.
- Output impact: creates IntakeTurn records and candidate ExtractedFact coverage.

2. Targeted Clarification
- Short freeform prompts for unresolved high-impact ambiguity.
- Output impact: updates ClarificationItem and DecisionItem candidates.

3. Alignment MCQ
- Constrained options to lock operating choices quickly.
- Output impact: converts ambiguity into explicit DecisionItems with lock_state changes.

4. Contradiction Resolution
- Forced conflict surfacing when two claims cannot coexist.
- Output impact: resolves Contradiction or marks one side UNKNOWN by explicit user choice.

Canonical MCQ policy:
- Option shape: 3 to 5 concrete options.
- Required option: none fit.
- Required path: custom input path if none fit is selected.
- Each option must map to target_decision_refs and expected lock effect.
- If user skips, system records unresolved state instead of guessing.

Information gain heuristic:
- Score each ClarificationItem by: uncertainty_reduction, contradiction_impact, cross-role_impact, effort_cost.
- Ask highest score first, but cap consecutive high-effort prompts.
- Recompute queue after each answer.

Fatigue control policy:
- Max high-friction prompts per round: 3.
- If unresolved queue remains high after two rounds, offer defer path with explicit UNKNOWN carry-forward.
- Trigger pause when user friction signals increase (skip rate, answer brevity, repeated none fit).

Contradiction handling:
- Contradiction classes: scope, temporal, priority, policy.
- Blocking contradictions must resolve before commit.
- Non-blocking contradictions can carry to RISKS_OPEN_QUESTIONS with explicit status and evidence.

Worked example 1: messy statement to DecisionItems and MCQs
- Intake statement: "I want premium quality but very simple onboarding, maybe subscription or maybe one-time, and fast outcomes without pressure."
- DecisionItems created:
  - brand_posture status USER_SAID with evidence_refs to statement segment.
  - onboarding_complexity status USER_SAID.
  - pricing_model status UNKNOWN.
  - outcome_pacing_tension status ASSUMED pending confirmation.
- MCQs generated:
  - pricing_model options: subscription-first, one-time-first, hybrid, undecided, none fit.
  - outcome_pacing options: speed-priority, comfort-priority, dual-metric, undecided, none fit.

Worked example 2: UNKNOWN survives into docs
- Intake statement: "We may need a district platform integration later, not sure which one."
- System behavior:
  - Create DecisionItem integration_target with status UNKNOWN and evidence_refs.
  - Add ClarificationItem with deferred resolution.
  - Assembly includes UNKNOWN in INTEGRATIONS and RISKS_OPEN_QUESTIONS.
  - Validation passes only if UNKNOWN remains explicit and no certainty language is introduced.

OPEN BOUNDARY: MCQ adaptation style
- Option A: fixed concise MCQ templates with custom branch.
- Option B: fully dynamic option writing each run.
- Option C: hybrid anchored options plus dynamic wording.
- Recommended default: Option C.
