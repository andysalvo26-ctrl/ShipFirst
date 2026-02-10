Validation and Gates

Validation objective:
- Prevent trust violations and structural drift.
- Allow concise, personalized outputs without template collapse.

Issue taxonomy:
- StructuralIssue: missing required artifact, missing required spine section, wrong role count.
- TrustIssue: missing status, missing evidence_refs, silent inference detected.
- ConsistencyIssue: unresolved blocking contradiction, orphan requirement, cross-doc conflict.
- BudgetIssue: word count outside hard min or hard max, Builder Notes count outside limits.
- DeterminismIssue: missing run identity, missing version tuple, idempotency collision mismatch.
- QualityIssue: low specificity, repetitive wording, generic filler.
- RetrievalIssue: embeddings unavailable or stale beyond policy.

Severity mapping:
- Block: StructuralIssue, TrustIssue, blocking ConsistencyIssue, hard BudgetIssue, DeterminismIssue.
- Warn: non-blocking ConsistencyIssue, soft-target budget drift, QualityIssue, RetrievalIssue with fallback active.
- Info: optimization hints only.

Contradiction severity policy:
- Critical contradictions block commit.
- Major contradictions block unless explicitly downgraded by rule profile with rationale.
- Minor contradictions warn and route to RISKS_OPEN_QUESTIONS.

Gate sequence:
- Gate A DiscoveryReady: intake exists and minimum coverage trace is present.
- Gate B AmbiguityReady: Unknown, Assumption, Contradiction, Clarification artifacts exist.
- Gate C ConfirmationReady: required DecisionItems classified; blockers resolved or explicitly deferred by policy.
- Gate D AssemblyReady: exactly 10 role docs drafted with required spine and Builder Notes.
- Gate E ConsistencyPass: no block-level issues remain.
- Gate F CommitAuthorized: idempotency and version metadata valid; commit atomically recorded.

Commit semantics:
- Commit is all-or-nothing for one ContractVersion.
- If commit fails, no partial committed version exists.
- Re-run with same idempotency context returns same commit reference or same failure class.

UNKNOWN survival checks:
- UNKNOWN in DecisionItem must remain UNKNOWN in downstream Requirement unless explicit confirmation event exists.
- Unknown-to-certain upgrade without confirmation is a TrustIssue and blocks commit.

Creativity guard checks:
- Repetition check warns when role prose overlaps above threshold with unrelated projects.
- Genericness check warns when claim specificity is below threshold.
- These checks cannot block commit unless they hide trust-critical information.

OPEN BOUNDARY: quality gating strictness
- Option A: quality checks always warn.
- Option B: repeated severe quality failures escalate to block.
- Option C: quality checks disabled in early phases.
- Recommended default: Option B.
