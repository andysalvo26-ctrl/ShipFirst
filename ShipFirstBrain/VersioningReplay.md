# Versioning and Replay

Purpose:
- Keep evolution safe without invalidating historical contracts.
- Guarantee structural replay at the brain-contract level.

## Version tuple (record on each run and commit)
- prompt_pack_version
- state_machine_version
- record_contract_version
- ten_docs_contract_version
- validation_profile_version
- retrieval_profile_version

## Change classes
- Patch: wording and tuning changes with no structural impact.
- Minor: additive fields/modules and non-breaking validation updates.
- Major: breaking stage I/O, role contract semantics, or gate semantics.

## Compatibility rules
- Historical contract versions remain immutable and valid under original tuple.
- New runs use default tuple unless a project pin is set.
- Comparison reports must declare comparison mode and expected variance.

## Replay policy
Required consistency under same tuple and input fingerprint:
- Same stage artifact shapes and required fields.
- Same role IDs and role count.
- Same status and provenance rules.
- Same block vs warn outcomes for trust-critical validations.

Allowed variance:
- Language phrasing and examples may vary within role budgets and spine constraints.

Prohibited variance:
- Silent status changes.
- Missing evidence/provenance requirements.
- Role ID drift.
- Commit semantic drift.

## Upgrade policy
- Each prompt-pack upgrade requires changelog and expected behavior delta.
- Major upgrades require migration note and risk acknowledgment.
- Prior UNKNOWN states are never auto-reinterpreted as certain.

OPEN BOUNDARY: tuple pinning
- Option A: always latest tuple.
- Option B: project-level pinned tuple with explicit upgrade.
- Option C: cycle-level ad hoc tuple selection.
- Recommended default: Option B.
