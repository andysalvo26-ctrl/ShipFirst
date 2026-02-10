# Brain Laws

These laws are mandatory. If any law is violated, commit is blocked.

1. Explicit Claim Law
- Every meaningful claim is a `DecisionItem` with one status: `USER_SAID`, `ASSUMED`, or `UNKNOWN`.

2. No Silent Inference Law
- Inferred meaning cannot appear in requirements or documents until recorded as a `DecisionItem` with evidence references.

3. Immutable Intake Law
- `IntakeTurn` is append-only.

4. Provenance Law
- Every `Requirement` must resolve to evidence from intake and decision lineage.

5. Ten-Role Cardinality Law
- Each committed contract version has exactly 10 documents with fixed role IDs.

6. Light-Spine Law
- Every role document follows required spine sections and budget constraints while language remains adaptive.

7. Unknown Preservation Law
- `UNKNOWN` is valid, explicit, and carried forward until confirmed.

8. Contradiction Visibility Law
- Contradictions are first-class records with severity and resolution state.

9. Fail-Closed Law
- Trust and structure validators fail closed.

10. Idempotent Run Law
- Same cycle, stage, input fingerprint, and version tuple yield the same run identity.

11. Immutable Commit Law
- `ContractVersion` is immutable after commit; updates occur only through new cycles.

12. Brain-Only Scope Law
- Brain output ends at committed/exportable contract packet; it does not build the app.

Refusal conditions:
- Missing status on any requirement.
- Missing evidence references on any requirement.
- Fewer or more than 10 role documents.
- Unresolved blocking contradiction at commit.
- Builder Notes outside 3 to 6 bullets in any role document.
- Hard budget violation in any role document.

OPEN BOUNDARY: confidence usage
- Option A: ranking aid only.
- Option B: ranking plus warning tuning.
- Option C: not stored.
- Recommended default: Option A.
