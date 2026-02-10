Versioning and Replay

Purpose:
- Allow brain evolution without invalidating prior contracts.
- Keep historical decisions auditable and reproducible at structure level.

Version tuple recorded on every GenerationRun and ContractVersion:
- prompt_pack_version
- state_machine_version
- record_contract_version
- ten_docs_contract_version
- validation_profile_version
- retrieval_profile_version

Change types:
- Patch: wording improvements, non-structural tuning.
- Minor: additive fields, additive modules, validator tuning without breaking contracts.
- Major: stage I/O changes, role contract break, gate semantics break.

Compatibility rules:
- Historical versions are immutable and evaluated under their original tuple.
- New runs default to current tuple unless project-level pin is active.
- Cross-version comparison reports must declare comparison mode and limits.

Replay policy:
- Required: structural replay consistency for stage outputs, role count, statuses, evidence_refs presence, and gate outcomes.
- Allowed variance: language phrasing may differ within role budgets and trust constraints.
- Prohibited variance: silent status changes, missing provenance, role ID changes, altered commit semantics.

Upgrade policy:
- Prompt pack upgrades require changelog entry and expected behavior delta.
- Major upgrades require migration notes and explicit risk acknowledgment.
- No automatic reinterpretation of past UNKNOWN items.

OPEN BOUNDARY: default version pinning
- Option A: always latest tuple.
- Option B: project-level pinned tuple with explicit upgrade action.
- Option C: cycle-level free choice.
- Recommended default: Option B.
