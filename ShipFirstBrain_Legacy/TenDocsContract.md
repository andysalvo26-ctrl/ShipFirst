Ten-Doc Contract

Fixed role IDs (unchanged):
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

Role budget model:
- Each role has soft target, hard minimum, and hard maximum words.
- Validation blocks on hard min and hard max failures.
- Validation warns on soft target drift.

Role definitions and budgets:
- NORTH_STAR: purpose is intent and success anchor; soft target 120; hard min 90; hard max 150.
- USER_STORY_MAP: purpose is actor journeys and key moments; soft target 220; hard min 170; hard max 270.
- SCOPE_BOUNDARY: purpose is in, out, defer boundaries; soft target 160; hard min 120; hard max 200.
- FEATURES_PRIORITIZED: purpose is ranked capabilities and tradeoffs; soft target 220; hard min 170; hard max 280.
- DATA_MODEL: purpose is conceptual entities and lifecycle constraints; soft target 220; hard min 170; hard max 280.
- INTEGRATIONS: purpose is external dependencies and unknowns; soft target 160; hard min 120; hard max 210.
- UX_NOTES: purpose is interaction principles and tone constraints; soft target 180; hard min 140; hard max 230.
- RISKS_OPEN_QUESTIONS: purpose is unresolved risks and pending choices; soft target 180; hard min 140; hard max 240.
- BUILD_PLAN: purpose is phased sequencing and dependencies for human implementation planning only; it never implies the brain generates code or executes builds; soft target 220; hard min 170; hard max 280.
- ACCEPTANCE_TESTS: purpose is measurable acceptance and rejection checks; soft target 220; hard min 170; hard max 280.

Required spine for every role document:
- Purpose statement in one to two lines.
- Key decisions with status labels.
- Acceptance criteria and success measures.
- Explicit UNKNOWN items if unresolved.
- Builder Notes section with 3 to 6 bullets.

Adaptive modules (optional, max two per role):
- Compliance nuance module.
- Audience and tone module.
- Temporal cadence module.
- Data sensitivity module.
- Differentiation module.

Trust rules at document level:
- Every requirement line must include status and evidence_refs.
- ASSUMED claims must include rationale and confirmation path.
- UNKNOWN claims must include why unresolved and where they are carried.

Creativity without templates mechanism:
- Keep section order stable but wording adaptive.
- Apply project language palette derived from intake terms and tone cues.
- Enforce anti-carbon-copy checks:
  - repeated phrase density threshold across unrelated projects,
  - generic filler phrase detection,
  - low-specificity warning when claims lack concrete nouns or constraints.
- Permit stylistic variance only if trust labels and spine constraints remain intact.

Builder Notes rules:
- Exactly one Builder Notes section per role document.
- 3 to 6 bullets only.
- Bullets must be actionable, scope-safe, and may include unresolved UNKNOWN implications.
