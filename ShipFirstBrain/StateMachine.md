# State Machine

Fixed pipeline:
`Discovery -> Extraction -> Ambiguity -> Confirmation -> Assembly -> Consistency -> Commit`

## Stage contracts

| Stage | Required input | Required output | Allowed assumptions | Must refuse | Done condition |
| --- | --- | --- | --- | --- | --- |
| Discovery | Active `Cycle`; new `IntakeTurn` entries | Discovery stage artifact; coverage summary | User language can be broad and non-technical | Editing prior intake turns | Coverage threshold reached or user explicitly advances |
| Extraction | Discovery artifact; version tuple | `ExtractedFact` set with evidence references | Multiple interpretations can coexist | Facts without evidence references | Output passes extraction shape checks |
| Ambiguity | `ExtractedFact`; current `DecisionItem` set | `ClarificationItem` queue; `Contradiction` set; updated `DecisionItem` statuses for assumptions and unknowns | Uncertainty is expected | Silent contradiction resolution | Queue is prioritized and contradiction severities assigned |
| Confirmation | Clarification queue; user responses | Updated `DecisionItem` set with lock states | Non-critical unknowns may remain explicit | Progress with unresolved blocking contradictions | Required decision coverage met and blockers resolved/deferred by policy |
| Assembly | Locked and explicit unresolved `DecisionItem` set | Draft `ContractDoc` set for all 10 role IDs; draft `Requirement` set | Titles and phrasing may vary | Any role-count mismatch; requirements without status | All role spines present and budgets within hard bounds |
| Consistency | Draft docs; requirements; provenance graph | `IssueReport` with severity map and remediation targets | Stylistic variance is acceptable | Orphan requirements; missing lineage; status/provenance drift | No block-level issues remain |
| Commit | Consistency pass; run identity; artifact fingerprint | Immutable `ContractVersion`; export metadata; `AuditEvent` trail | Parent version may exist | Partial writes; duplicate commit conflict | Atomic commit acknowledged |

## Transition rules
- Transitions are forward-only unless a remediation transition is recorded.
- Return transitions must reference an `IssueReport` item.
- Confirmation cannot be skipped.

## Stop and rollback rules
- Stop immediately on trust-critical failures.
- Pause on fatigue threshold and preserve queue state.
- Rollback is logical, not destructive: create new derived artifacts and events; immutable records remain unchanged.
- Commit failure creates no partial `ContractVersion`.

OPEN BOUNDARY: discovery-to-confirmation threshold
- Option A: fixed count of locked decisions.
- Option B: weighted coverage across all 10 role IDs.
- Option C: user-controlled advance with warnings.
- Recommended default: Option B.
