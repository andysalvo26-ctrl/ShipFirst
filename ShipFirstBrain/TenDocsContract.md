# Ten-Docs Contract

Fixed role IDs (must not change):
1. NORTH_STAR
2. USER_STORY_MAP
3. SCOPE_BOUNDARY
4. FEATURES_PRIORITIZED
5. DATA_MODEL
6. INTEGRATIONS
7. UX_NOTES
8. RISKS_OPEN_QUESTIONS
9. BUILD_PLAN
10. ACCEPTANCE_TESTS

## Budget policy
- Every role has a soft target, hard minimum, and hard maximum.
- Hard min and hard max violations are block-level.
- Soft-target drift is warning-level.

| Role ID | Purpose | Soft target | Hard min | Hard max |
| --- | --- | --- | --- | --- |
| NORTH_STAR | Intent and success anchor | 120 | 90 | 150 |
| USER_STORY_MAP | Actors, journeys, edge moments | 220 | 170 | 270 |
| SCOPE_BOUNDARY | In, out, defer boundaries | 160 | 120 | 200 |
| FEATURES_PRIORITIZED | Ranked capabilities and tradeoffs | 220 | 170 | 280 |
| DATA_MODEL | Conceptual entities and lifecycle constraints | 220 | 170 | 280 |
| INTEGRATIONS | External dependencies and unresolved choices | 160 | 120 | 210 |
| UX_NOTES | Interaction and tone constraints | 180 | 140 | 230 |
| RISKS_OPEN_QUESTIONS | Explicit unresolved risk and unknown map | 180 | 140 | 240 |
| BUILD_PLAN | Human implementation sequencing and dependencies only | 220 | 170 | 280 |
| ACCEPTANCE_TESTS | Measurable acceptance and rejection checks | 220 | 170 | 280 |

## Required spine for every role document
- Purpose statement.
- Key decisions with status labels.
- Acceptance criteria and success measures.
- Explicit unknowns carried forward.
- Builder Notes section with 3 to 6 bullets.

## Adaptive modules (optional, max 2 per role)
- Compliance nuance.
- Audience and tone variation.
- Temporal cadence.
- Data sensitivity.
- Differentiation context.

## Trust requirements per requirement line
- Must include status: USER_SAID, ASSUMED, or UNKNOWN.
- Must include evidence references.
- ASSUMED requires rationale and confirmation path.
- UNKNOWN requires explicit unresolved reason and carry-forward location.

## Creativity without templates
- Keep structural spine fixed; vary language and examples per project.
- Build and apply project language palette from intake vocabulary and tone.
- Enforce anti-carbon-copy checks:
  - repeated phrase density threshold across unrelated projects,
  - generic filler detection,
  - low-specificity warning when claims lack concrete constraints.
- Builder Notes must be actionable and project-specific; formulaic notes trigger quality warnings.

Rule of scope:
- BUILD_PLAN and ACCEPTANCE_TESTS describe the contract for human execution; they do not imply the brain writes or ships the app.
