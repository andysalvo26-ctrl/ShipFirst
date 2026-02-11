# What We Quarantine
Status: Binding-Except-UNKNOWN

## Purpose
This document marks artifacts and patterns that must not be used as Kodos templates, while allowing compatibility where required. It reduces drift from stale docs and interaction assumptions. It distinguishes compatibility retention from design authority.

## Binding Statements
- Existing iOS view structure is compatibility evidence, not a template for Kodos interaction primitive.
- Legacy endpoint framing that centers `generate-docs` is quarantined from primary Kodos flow.
- Folders with conflicting “frozen truth” claims SHALL NOT be used as tie-breaker authorities.
- `ShipFirstPlatform/00_README.md` SHALL be treated as informational only until the referenced canonical file set actually exists.
- Compatibility retention is allowed for runtime safety, but quarantined items cannot define normative behavior.

## Definitions
- Quarantine: Material retained in repo for compatibility/history but excluded from design authority.
- Compatibility retention: Keeping endpoints or code paths available without using them as primary interaction contract.

## Evidence Pointers
- `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`
- `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`
- `supabase/functions/generate-docs/index.ts`
- `README.md`
- `ShipFirstBrain/README.md`
- `ShipFirstBrain_Canonical/01_Platform_Definition.md`
- `ShipFirstPlatform/00_README.md`
- `CANON_PRECEDENCE.md`

## UNKNOWN
- Whether `ShipFirstPlatform/01..10` documents are intentionally omitted or accidentally missing. Resolution evidence: populated `ShipFirstPlatform/` file set matching `00_README.md` references.
