# Questioning System

Objective:
- Capture intent with high information gain and low user fatigue.
- Convert ambiguity into explicit `DecisionItem` states.
- Preserve trust labels and provenance at every step.

## Question modes
1. Freeform Discovery
- Broad prompts for goals, constraints, audience, and edge cases.
- Output impact: new intake turns and candidate extracted facts.

2. Targeted Clarification
- Narrow freeform prompts for unresolved high-impact ambiguity.
- Output impact: clarified decision candidates and queue updates.

3. Alignment MCQ
- Constrained choices that lock meaning quickly.
- Output impact: decision lock-state changes with explicit status transitions.

4. Contradiction Resolution
- Focused conflict prompts when claims cannot coexist.
- Output impact: contradiction resolution or explicit preserved uncertainty.

## Canonical MCQ policy
- Option count: 3 to 5 concrete choices.
- Required options: `None fit` and `Custom input` path.
- Each option maps to target decision references and intended lock effect.
- Skip behavior never implies acceptance; skip preserves unresolved state.

## Information gain heuristic
Prioritize each clarification item by:
- uncertainty reduction,
- contradiction impact,
- cross-role contract impact,
- effort cost.

Ask highest-value items first with fatigue caps, then recompute queue after each response.

## Fatigue policy
- Maximum high-friction prompts per round: 3.
- If skip rate and low-information responses increase, pause and offer defer path.
- Deferred items remain explicit as `UNKNOWN` with rationale.

## Contradiction policy
- Contradiction classes: scope, temporal, priority, policy.
- Blocking classes must resolve before commit.
- Non-blocking classes can carry forward only with explicit labeling and evidence.

## Worked example 1: messy statement to decisions and MCQs
Input statement:
- "We want premium results, simple onboarding, maybe subscription or one-time, and fast outcomes without pressure."

Decision extraction:
- `brand_posture` -> USER_SAID with evidence.
- `onboarding_complexity` -> USER_SAID with evidence.
- `pricing_model` -> UNKNOWN pending clarification.
- `outcome_pacing_tradeoff` -> ASSUMED pending confirmation.

MCQ set:
- pricing model: subscription-first, one-time-first, hybrid, undecided, none fit, custom.
- pacing tradeoff: speed-first, comfort-first, dual-metric, undecided, none fit, custom.

## Worked example 2: UNKNOWN survival
Input statement:
- "We may need an external school platform later, not sure which one."

System behavior:
- Create decision item with status UNKNOWN and evidence.
- Add clarification item and defer path.
- Carry UNKNOWN into INTEGRATIONS and RISKS_OPEN_QUESTIONS.
- Validation blocks any silent conversion to certainty.

OPEN BOUNDARY: MCQ style control
- Option A: mostly fixed options with adaptive wording.
- Option B: fully dynamic options each run.
- Option C: fixed skeleton with adaptive tails.
- Recommended default: Option C.
