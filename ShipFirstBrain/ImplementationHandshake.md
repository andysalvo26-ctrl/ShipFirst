# Implementation Handshake (Word-Only)

Purpose:
- Define the minimum operations an implementation must provide.
- Keep boundaries clear so builders do not guess core behavior.

Required operations:

1) CreateProject
- Input: owner identity and project metadata.
- Output: project reference and initial cycle reference.

2) AppendIntakeTurn
- Input: cycle reference, actor type, raw text, timestamp context.
- Output: immutable intake turn reference and updated discovery coverage summary.

3) RunStage
- Input: cycle reference, stage name, version tuple, run identity seed, input fingerprint.
- Output: stage artifacts, issue references, and run status.

4) ListClarificationQueue
- Input: cycle reference and optional filter.
- Output: prioritized clarification queue with fatigue and impact metadata.

5) ResolveClarificationItem
- Input: clarification reference, selected option or custom response, actor identity.
- Output: updated decision items, contradiction deltas, and queue updates.

6) AssembleTenDocsDraft
- Input: cycle reference, classified decision set, unresolved unknown set, ten-doc contract version.
- Output: exactly 10 role docs, requirement set, builder notes sections.

7) ValidateDraftPacket
- Input: draft packet reference and validation profile version.
- Output: issue list by severity and gate recommendation.

8) CommitContractVersion
- Input: cycle reference, validation pass reference, commit idempotency key, actor identity.
- Output: immutable contract version reference, artifact fingerprint, audit trail references.

9) ExportContractPacket
- Input: committed contract version reference and export profile.
- Output: packet manifest with docs, provenance map, and run summary.

10) StartChangeCycle
- Input: project reference, parent contract version reference, change request.
- Output: new cycle linked to parent version with initialized stage state.

Idempotency rules:
- Run identity derives from cycle, stage, input fingerprint, and version tuple.
- Repeated run with same identity returns same artifact references or same failure class.
- Commit with same idempotency key and fingerprint returns same commit result.

Commit rules:
- Atomic commit only.
- No partial committed state on failure.
- Supersession occurs through new cycle; historical versions are never mutated.

Minimum metadata on all operations:
- actor_ref, cycle_ref, timestamp, correlation_ref, version tuple, audit category.

Scope guard:
- These operations define interviewer and contract generation behavior only.
- No operation here generates code or executes app implementation from the 10 docs.
