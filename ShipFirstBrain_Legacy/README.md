ShipFirstBrain

What this folder is:
- The canonical, implementation-ready specification for one capability only: an adaptive interviewer that outputs exactly 10 contract documents.
- The deterministic structure for intent capture, ambiguity handling, contradiction resolution, provenance enforcement, and contract commit.
- The trust layer that must remain stable even when downstream implementation workflows change.

What this folder is not:
- Not an app builder.
- Not runtime architecture.
- Not deployment, hosting, or product feature planning.

Core output contract:
- Exactly 10 document roles per committed version.
- Every requirement carries status and evidence_refs.
- Every document includes Builder Notes (3 to 6 bullets).
- Documents are concise, high-signal, and personalized without breaking spine rules.

Trust posture:
- No silent inference.
- USER_SAID, ASSUMED, UNKNOWN are the only allowed claim statuses.
- UNKNOWN is preserved when unresolved; it is never silently converted to certainty.

How to read this folder:
1. Brain_Laws.md
2. StateMachine.md
3. RecordModel.md
4. TenDocsContract.md
5. ValidationAndGates.md
6. QuestioningSystem.md
7. EmbeddingsPlan.md
8. VersioningReplay.md
9. ImplementationHandshake.md
10. AUDIT.md

Deterministic vs flexible:
- Deterministic: stage contracts, record semantics, gate behavior, role IDs, validation rules.
- Flexible: language style, question wording, adaptive modules, doc title phrasing.

Drift checklist:
- If a change helps generate code, deploy systems, or define product implementation, it is likely out of scope.
- If a change weakens provenance, status labeling, or gate strictness, it is not allowed.
- If a change causes 10 docs to become template clones, quality has drifted and must be corrected.
