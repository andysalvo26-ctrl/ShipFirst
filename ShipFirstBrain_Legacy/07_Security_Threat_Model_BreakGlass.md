# Security, Threat Model, and Break-Glass

## Threat model focus (Phase 1)
- Tenant data leakage through incorrect RLS.
- Ownership spoofing on project creation.
- Service-role misuse bypassing user ownership checks.
- Silent schema drift causing undefined behavior and partial writes.
- Unauthorized artifact access in storage.

## Required controls
1. RLS default deny on customer-path tables.
2. Ownership checks via `user_owns_project(project_id)` for project-scoped data.
3. Project ownership anti-spoof controls (default + trigger + RLS check).
4. Server-only writes for generation/contract/submission/audit tables.
5. Structured error layering to avoid false auth diagnoses.
6. Private submission bucket and scoped access.

## Privileged action policy
- Privileged actions:
  - migration execution,
  - policy reset,
  - incident break-glass access.
- Privileged actions SHALL be logged in auditable operational records.

## Break-glass posture
- Allowed only for active incident containment or data recovery.
- Must include operator identity, reason, scope, and timestamp.
- Requires post-incident reconciliation:
  - what changed,
  - why normal controls were insufficient,
  - which migration/policy change prevents recurrence.

## Out-of-scope security work (Phase 1)
- Enterprise org IAM models.
- External SIEM integration.
- Advanced key management outside Supabase secret boundary.
