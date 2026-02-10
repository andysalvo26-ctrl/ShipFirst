# Record Model (Conceptual)

Purpose:
- Define the minimal conceptual entities required by the state machine.
- Keep naming and flow consistent with stage contracts.

## Core entities
- `Project`: id, owner_ref, created_at, active_cycle_ref, project_state.
- `Cycle`: id, project_ref, parent_contract_version_ref, stage_state, started_at, ended_at.
- `IntakeTurn`: id, cycle_ref, turn_index, actor_type, raw_text, timestamp, immutable_flag.
- `StageArtifact`: id, cycle_ref, stage_name, artifact_type, payload_ref, version_tuple, created_at.
- `ExtractedFact`: id, cycle_ref, claim, fact_type, evidence_refs, confidence, created_at.
- `DecisionItem`: id, cycle_ref, claim, status, evidence_refs, confidence, lock_state, rationale, updated_at.
- `ClarificationItem`: id, cycle_ref, prompt_text, option_set, target_decision_refs, priority_score, fatigue_weight, resolution_state.
- `Contradiction`: id, cycle_ref, contradiction_type, conflicting_refs, severity, resolution_state, opened_at, closed_at.
- `Requirement`: id, contract_doc_ref, claim, status, evidence_refs, acceptance_criteria, success_measure, priority_level.
- `ProvenanceLink`: id, source_ref, target_ref, link_type, excerpt, created_at.
- `ContractDoc`: id, contract_version_ref, role_id, title_text, body_text, word_count, builder_notes_count.
- `ContractVersion`: id, project_ref, cycle_ref, version_label, parent_version_ref, artifact_fingerprint, committed_at.
- `GenerationRun`: id, cycle_ref, stage_name, run_identity, input_fingerprint, output_fingerprint, run_status, started_at, ended_at.
- `IssueReport`: id, cycle_ref, stage_name, issue_type, severity, issue_ref, remediation_state, created_at.
- `AuditEvent`: id, project_ref, cycle_ref, actor_ref, event_type, payload_summary, created_at.
- `EmbeddingRecord`: id, source_ref, source_type, embedding_profile_ref, staleness_state, created_at.

## Derived views
- Unknown set: `DecisionItem` where status is `UNKNOWN`.
- Assumption set: `DecisionItem` where status is `ASSUMED`.
- Locked set: `DecisionItem` where lock_state is locked.

## Relationship spine
- Project has many cycles.
- Cycle owns intake, extraction, ambiguity, decision, issue, run, and audit records.
- Cycle produces contract versions through commit.
- ContractVersion contains exactly 10 ContractDocs by fixed role ID.
- ContractDoc contains requirements.
- ProvenanceLink binds requirement and decision lineage back to intake evidence.
- EmbeddingRecord indexes text for retrieval support only.

## Provenance guarantees
- Each requirement must have lineage to decision and intake evidence.
- `UNKNOWN` requirements must still include evidence and explicit unresolved rationale.

## Stage-to-record map
- Discovery writes IntakeTurn and StageArtifact coverage summary.
- Extraction writes ExtractedFact and StageArtifact extraction summary.
- Ambiguity writes ClarificationItem, Contradiction, and DecisionItem status updates.
- Confirmation updates DecisionItem lock and status fields.
- Assembly writes draft ContractDoc and Requirement records.
- Consistency writes IssueReport and stage artifact outputs.
- Commit writes immutable ContractVersion and commit AuditEvents.
