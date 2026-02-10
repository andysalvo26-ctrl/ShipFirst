# ShipFirst Brain Constitution (Frozen)

This folder defines the frozen, authoritative specification for ShipFirst Brain: an adaptive interviewer that converts messy intent into exactly 10 concise contract documents.

Scope (in):
- Interview flow from discovery to commit.
- Decision formalization with statuses `USER_SAID`, `ASSUMED`, `UNKNOWN`.
- Provenance and trust guarantees.
- Ten-document contract generation, validation, versioning, and export semantics.

Scope (out):
- App implementation from the contract packet.
- Runtime product architecture, deployment, or code generation.

Constitutional guarantees:
- No silent inference.
- Exactly 10 fixed role IDs per committed contract version.
- Every requirement includes status and evidence references.
- Unknowns remain explicit until resolved by a user-confirmed decision.

Deterministic vs flexible:
- Deterministic: stage contracts, record semantics, gate behavior, role IDs, version tuple, commit semantics.
- Flexible: question phrasing, optional adaptive modules, writing style, document titles.

Canonical reading order:
1. `Brain_Laws.md`
2. `StateMachine.md`
3. `RecordModel.md`
4. `QuestioningSystem.md`
5. `EmbeddingsPlan.md`
6. `TenDocsContract.md`
7. `ValidationAndGates.md`
8. `VersioningReplay.md`
9. `ImplementationHandshake.md`

Governance rule:
- These files are frozen truth for implementation.
- Revisions require explicit governance update and new version declaration.
