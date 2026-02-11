# Security, Threat Model, and Break-Glass (Phase 1 Canonical)

## Why this exists
This document keeps security decisions tied to actual Phase 1 risks instead of abstract policy language. It defines what we must protect now so users can trust that captured meaning and submitted artifacts are isolated and auditable. It also defines how emergency access is handled without normalizing unsafe shortcuts.

## Phase 1 primary risks
- Cross-tenant access caused by policy drift.
- Ownership spoofing during project creation or write operations.
- Silent schema drift causing partial writes or incorrect behavior.
- Service-role misuse outside approved server boundaries.
- Unauthorized access to submission bundle artifacts.

## Required controls
1. RLS enabled on all customer-path tables.
2. Ownership checks applied before every project-scoped server write.
3. Client contains no provider/service secrets.
4. Private submission storage bucket and recorded artifact path.
5. Structured audit records for privileged or system writes.

## Break-glass policy (Phase 1)
- Allowed only for active incident response or recovery.
- Must record operator identity, reason, scope, and timestamp.
- Must result in a follow-up remediation change (migration, policy, or check update).

## Out of scope for Phase 1
- Enterprise IAM integrations.
- Full SIEM pipeline.
- Expanded org hierarchy beyond current ownership model.
