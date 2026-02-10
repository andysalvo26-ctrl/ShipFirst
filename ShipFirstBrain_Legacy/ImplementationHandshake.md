Implementation Handshake (Word-Only)

Purpose:
- Define the minimum conceptual operations future implementation must provide.
- Remove guesswork while keeping architecture choices open.

Required operations and semantic contracts:

1. CreateProject
- Input: owner identity and project metadata.
- Output: Project reference and initial Cycle reference.

2. AppendIntakeTurn
- Input: cycle reference, actor type, raw text, timestamp context.
- Output: immutable IntakeTurn reference and updated discovery coverage summary.

3. RunStage
- Input: cycle reference, stage name, run identity seed, version tuple, input fingerprint.
- Output: stage artifacts and stage status with issue summary.

4. ListClarificationQueue
- Input: cycle reference and queue filter.
- Output: prioritized ClarificationItem list with fatigue and impact metadata.

5. ResolveClarificationItem
- Input: clarification reference, selected option or custom text, actor reference.
- Output: updated DecisionItem states and contradiction deltas.

6. AssembleTenDocsDraft
- Input: cycle reference, decision set, unresolved UNKNOWN set, ten-doc contract version.
- Output: exactly 10 role docs with Requirement records and Builder Notes sections.

7. ValidateDraftPacket
- Input: draft packet reference and validation profile version.
- Output: issue list with block or warn severity and remediation targets.

8. CommitContractVersion
- Input: cycle reference, validation pass proof, commit idempotency key, actor reference.
- Output: immutable ContractVersion reference, artifact fingerprint, audit trail references.

9. ExportContractPacket
- Input: committed ContractVersion reference and export profile.
- Output: packet manifest reference with docs, provenance map, and run summary.

10. StartChangeCycle
- Input: project reference, parent ContractVersion reference, change request text.
- Output: new Cycle reference linked to parent version and initialized stage state.

Idempotency semantics:
- Run identity is derived from cycle, stage, input fingerprint, and version tuple.
- Duplicate stage requests with same identity return same artifact references.
- Commit with same idempotency key and fingerprint returns same commit result.

Commit semantics:
- Atomic commit only.
- No partial ContractVersion write on failure.
- Supersession is additive through StartChangeCycle, never in-place mutation.

Minimum metadata required on every operation:
- actor_ref, cycle_ref, timestamp, version tuple, correlation_ref, audit category.

Out-of-scope safeguard:
- No operation here generates application code or executes app implementation from the 10 docs.
