# Product Surfaces Contract

## Intake Surface (Phase 1 active)
Role:
- Guided interviewer with open discovery, constrained confirmations, and explicit unknown handling.

Users:
- Customer users.

Outputs:
- Intake turns, decision items, generated contract docs, submission bundle reference.

Non-goals:
- No runtime app operations.
- No customer infrastructure control.
- No auto-build from docs to shipped app.

## Customer Console (future)
Role:
- Operational configuration for customer live apps.

Users:
- Customer admins/operators.

Phase 1 status:
- Out of scope.

## Runtime Apps (future)
Role:
- Customer-facing experiences (web subdomains + iOS subapps).

Users:
- End users of customer businesses.

Phase 1 status:
- Out of scope for productized operation; only identifier contracts are defined.

## Dev Central (Phase 1 minimal internal)
Role:
- Internal operator control for migration governance and incident triage.

Allowed in Phase 1:
- View tenant/project/cycle state.
- Run approved migrations.
- Inspect generation/submit failures with correlation context.
- Execute audited break-glass operations.

Not allowed in Phase 1:
- Direct customer content editing.
- Runtime behavior overrides without governed change flow.
- Untracked SQL edits outside migration or break-glass process.

## ShipFirst Website
Role:
- Public docs and onboarding entry only.

Phase 1 status:
- Allowed as entry surface; not part of control-plane operations.
