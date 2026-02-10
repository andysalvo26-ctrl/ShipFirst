# Validation and Gates

Validation intent:
- Enforce trust and structural integrity.
- Permit creative expression within deterministic boundaries.

## Issue taxonomy
- StructuralIssue: missing artifact, wrong role count, missing required spine section.
- TrustIssue: missing status, missing evidence, silent inference, illegal status transition.
- ConsistencyIssue: unresolved contradiction, cross-doc conflict, orphan requirement.
- BudgetIssue: hard min/max or builder-notes count violations.
- DeterminismIssue: missing run identity, version tuple mismatch, idempotency conflict.
- QualityIssue: repetitive output, generic phrasing, low specificity.
- RetrievalIssue: embedding unavailable or stale beyond policy.

## Severity matrix
- Block: StructuralIssue, TrustIssue, blocking ConsistencyIssue, hard BudgetIssue, DeterminismIssue.
- Warn: non-blocking ConsistencyIssue, soft budget drift, QualityIssue, RetrievalIssue with fallback active.
- Info: non-actionable optimization hints.

## Contradiction severity to gate behavior
- Critical: always block.
- Major: block by default; downgrade requires explicit rule profile and audit rationale.
- Minor: warn and carry to RISKS_OPEN_QUESTIONS.

## Gate sequence
- Gate A DiscoveryReady: intake exists and coverage trace exists.
- Gate B AmbiguityReady: clarification queue, contradiction map, unknown and assumption sets exist.
- Gate C ConfirmationReady: required decision coverage met; blocking contradictions resolved/deferred by policy.
- Gate D AssemblyReady: exactly 10 docs with required spine and Builder Notes.
- Gate E ConsistencyPass: no block-level issues.
- Gate F CommitAuthorized: idempotency, version metadata, and atomic write preconditions pass.

## Commit semantics
- Commit is all-or-nothing for one contract version.
- Failed commit yields no partial committed state.
- Repeated commit with same idempotency context returns same result class.

## UNKNOWN survival enforcement
- UNKNOWN in DecisionItem must remain UNKNOWN downstream unless explicit confirmation event exists.
- Unknown-to-certain without confirmation is TrustIssue and blocks commit.

## Creativity guard enforcement
- Repetition and genericness checks are mandatory quality checks.
- Quality checks escalate to block only when they conceal trust-critical meaning.

OPEN BOUNDARY: quality escalation policy
- Option A: quality is always warning-only.
- Option B: repeated severe quality failures escalate to block.
- Option C: quality checks disabled in early cycles.
- Recommended default: Option B.
