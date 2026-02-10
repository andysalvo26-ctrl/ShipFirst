Record Model (Conceptual)

Purpose:
- Define the minimum record set required for the interviewer pipeline.
- Keep names consistent with stage contracts.
- Avoid database-specific schema lock-in.

Core entities and fields:
- Project has: id, owner_ref, created_at, active_cycle_ref, project_state.
- Cycle has: id, project_ref, parent_contract_version_ref, stage_state, started_at, ended_at.
- IntakeTurn has: id, cycle_ref, turn_index, actor_type, raw_text, timestamp, immutable_flag.
- ExtractedFact has: id, cycle_ref, claim, fact_type, evidence_refs, confidence, created_at.
- DecisionItem has: id, cycle_ref, claim, status, evidence_refs, confidence, lock_state, rationale, updated_at.
- ClarificationItem has: id, cycle_ref, prompt_text, option_set, target_decision_refs, priority_score, fatigue_weight, resolution_state.
- Contradiction has: id, cycle_ref, contradiction_type, conflicting_refs, severity, resolution_state, opened_at, closed_at.
- Requirement has: id, contract_doc_ref, claim, status, evidence_refs, acceptance_criteria, success_measure, priority_level.
- ProvenanceLink has: id, source_ref, target_ref, link_type, excerpt, created_at.
- ContractDoc has: id, contract_version_ref, role_id, title_text, body_text, word_count, builder_notes_count.
- ContractVersion has: id, project_ref, cycle_ref, version_label, parent_version_ref, artifact_fingerprint, committed_at.
- GenerationRun has: id, cycle_ref, stage_name, run_identity, input_fingerprint, output_fingerprint, run_status, started_at, ended_at.
- AuditEvent has: id, project_ref, cycle_ref, actor_ref, event_type, payload_summary, created_at.
- EmbeddingRecord has: id, source_ref, source_type, embedding_profile_ref, staleness_state, created_at.

Relationship spine:
- Project owns many Cycle records.
- Cycle owns IntakeTurn, ExtractedFact, DecisionItem, ClarificationItem, Contradiction, GenerationRun, and AuditEvent records.
- Cycle produces ContractVersion records through successful commit.
- ContractVersion contains exactly 10 ContractDoc records keyed by fixed role_id.
- ContractDoc contains Requirement records.
- ProvenanceLink connects Requirement and DecisionItem lineage back to IntakeTurn evidence.
- EmbeddingRecord indexes selected text artifacts for retrieval; it never replaces canonical records.

Provenance graph guarantees:
- Every Requirement must link to at least one DecisionItem and at least one IntakeTurn through evidence_refs or ProvenanceLink paths.
- If certainty is not available, status remains UNKNOWN and rationale is mandatory.

Stage-to-record production map:
- Discovery writes IntakeTurn and discovery coverage snapshots.
- Extraction writes ExtractedFact.
- Ambiguity writes ClarificationItem and Contradiction and may seed ASSUMED or UNKNOWN DecisionItems.
- Confirmation updates DecisionItem status and lock_state.
- Assembly writes ContractDoc drafts and Requirement drafts.
- Consistency writes IssueReport summaries to AuditEvent payloads.
- Commit writes immutable ContractVersion and final ContractDoc/Requirement snapshots.

Derived views used by stages:
- Unknown set is the subset of DecisionItem where status is UNKNOWN.
- Assumption set is the subset of DecisionItem where status is ASSUMED.
- No separate Unknown or Assumption entity is required.
