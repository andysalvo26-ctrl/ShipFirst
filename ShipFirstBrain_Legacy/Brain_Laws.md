ShipFirst Brain Laws

Non-negotiable laws:
1. Explicit Claim Law
- Every meaningful claim must exist as a DecisionItem with one status: USER_SAID, ASSUMED, or UNKNOWN.

2. No Silent Inference Law
- Inferred claims may influence output only after they are recorded as DecisionItems with evidence_refs and status.

3. Immutable Intake Law
- IntakeTurn records are append-only and cannot be edited in place.

4. Provenance Completeness Law
- Every Requirement must have evidence_refs that point to intake and decision lineage.

5. Ten-Role Cardinality Law
- Every committed contract version has exactly 10 documents with fixed role IDs.

6. Light-Spine Law
- Each role has a required minimal spine and strict word constraints; adaptive language is allowed inside that spine.

7. Unknown Preservation Law
- UNKNOWN is valid state and must remain explicit until resolved by user confirmation or later cycle.

8. Contradiction Visibility Law
- Contradictions are first-class records; hidden contradictions are invalid state.

9. Fail-Closed Law
- Trust-critical validator failures block commit.

10. Idempotent Run Law
- Same cycle input fingerprint and same version tuple must map to the same run identity.

11. Immutable Commit Law
- ContractVersion records are immutable; changes happen only via new cycle and new version.

12. Brain-Only Scope Law
- The brain ends at contract packet commit/export; downstream app implementation is out of scope.

Refusal rules:
- Refuse commit if any requirement is missing status.
- Refuse commit if any requirement is missing evidence_refs.
- Refuse commit if role count is not exactly 10.
- Refuse commit if blocking contradictions are unresolved.
- Refuse commit if Builder Notes count is outside 3 to 6 bullets in any role document.
- Refuse commit if document exceeds hard maximum words.

OPEN BOUNDARY: confidence handling
- Option A: store confidence for ranking only.
- Option B: store confidence and use it in warning thresholds.
- Option C: do not store confidence.
- Recommended default: Option A to avoid false precision in gate decisions.
