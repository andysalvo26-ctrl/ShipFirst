# Product Surfaces (Phase 1 Canonical)

## Why this exists
This document keeps surface scope explicit so Phase 1 remains shippable and trustworthy. It clarifies what users can do today versus what is planned later. It prevents accidental scope creep while preserving the long-term vision that owners will operate their own apps through ShipFirst.

## Surface map

| Surface | Phase 1 Status | Primary User | Primary Outcome | Explicit Non-goals in Phase 1 |
|---|---|---|---|---|
| Intake Surface | Active | Customer user | Complete one run to reviewed 10-doc packet + submission bundle | No runtime app operations, no app generation |
| Customer Console | Future | Customer operator/admin | Operate running app settings and business logic | Not built in Phase 1 |
| Runtime Apps | Future | End customer of ShipFirst customer | Use deployed customer app experiences | Not built in Phase 1 |
| Dev Central | Internal minimal | ShipFirst team | Keep migrations, incidents, and support operations controlled | No shadow customer-facing product surface |
| ShipFirst Website | Supporting | Prospective customers | Explain onboarding and direct users to intake | No control-plane responsibilities |

## Active surface contract (Intake)
- Intake starts open-ended and then moves into constrained confirmations.
- Alignment checkpoints include structured moments (including multiple-choice style).
- The flow never silently infers critical meaning.
- Users review all ten documents before final submit.

## Why this still supports owner-operated apps later
Phase 1 does not expose runtime controls yet, but it establishes the durable ownership and meaning contracts those controls require. This prevents later owner-facing operations from relying on ambiguous or unaudited assumptions.
