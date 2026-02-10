ShipFirst Brain State Machine

Stage sequence is fixed:
Discovery -> Extraction -> Ambiguity -> Confirmation -> Assembly -> Consistency -> Commit

Stage contracts:

| Stage | Required Inputs | Required Outputs | Allowed to Assume | Must Refuse | Done Condition |
| --- | --- | --- | --- | --- | --- |
| Discovery | active Cycle, append-only IntakeTurn stream | discovery coverage snapshot, normalized intake segments | user language may be messy or incomplete | edits to existing IntakeTurn records | minimum coverage reached or user explicitly advances |
| Extraction | normalized intake segments, version tuple | ExtractedFact records with evidence_refs | multiple interpretations can coexist | facts without evidence_refs | all extracted facts pass shape and provenance checks |
| Ambiguity | ExtractedFact set, prior DecisionItems | Unknown set, Assumption set, Contradiction set, ClarificationItem queue | unresolved uncertainty is expected | silent contradiction resolution | clarification queue produced with priority and fatigue weight |
| Confirmation | ClarificationItem queue, user responses | updated DecisionItems with status and lock_state | non-critical unknowns may remain | progression with unresolved blocking contradictions | required decision coverage achieved; blockers resolved or deferred by policy |
| Assembly | locked DecisionItems plus explicit UNKNOWNs | 10 ContractDoc drafts and Requirement set | role titles may vary | fewer or more than 10 role docs | all role IDs present with required spine sections |
| Consistency | ContractDoc drafts, Requirement set, provenance graph | issue report with severity and remediation targets | language can vary if claims are consistent | orphan requirements, missing statuses, broken lineage | no block-level issues remain |
| Commit | consistency pass, run identity, artifact fingerprint | immutable ContractVersion, export metadata, AuditEvent trail | parent version may exist | partial commit, duplicate commit for same idempotency key | commit acknowledged and version linked to cycle |

Transition rules:
- Transitions are one-way by default; remediation creates explicit return transition events.
- Any stage can route back to a previous stage only via IssueReport references.
- Confirmation cannot skip directly to Commit.

Stop and rollback conditions:
- Stop immediately on trust-critical validation failures.
- Stop on fatigue threshold and preserve queue state for resume.
- Rollback is logical, not destructive: create new derived artifacts; immutable records remain.
- Commit failure yields no partial ContractVersion.

OPEN BOUNDARY: open-to-constrained threshold
- Option A: fixed required count of locked DecisionItems.
- Option B: weighted coverage across all 10 role IDs.
- Option C: user-controlled advance with warnings.
- Recommended default: Option B.
