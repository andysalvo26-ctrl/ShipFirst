# Security and Governance

## Purpose
- Define enforceable boundaries for tenant isolation, secrets, service-role usage, and migration governance.
- Prevent emergency patches from bypassing security controls.

## Non-goals
- No full SOC2/GRC program design in this phase.
- No broad IAM redesign outside current Supabase + Edge setup.

## Decisions / Invariants
- Tenant isolation model:
  - Primary isolation is row-level ownership enforced via RLS.
  - `projects.owner_user_id` is authoritative tenancy root for project-scoped data.
- RLS philosophy:
  - Default deny.
  - Client can write only minimal intake-state tables.
  - Server-only tables are read-only to authenticated owners and writeable only via service-role paths.
- Service role boundary:
  - Allowed only inside Edge Functions for generation and submit workflows.
  - Never used from iOS client.
  - Service-role writes must still perform explicit ownership checks with user JWT context.
- Secrets boundary:
  - iOS ships only Supabase URL + anon key.
  - OpenAI/service-role keys live in Supabase secrets (`supabase/functions/.env` -> `supabase secrets set`).
- Migration governance:
  - All production schema changes are additive, idempotent migrations.
  - No ad hoc dashboard table edits unless break-glass procedure is invoked and documented.
- Break-glass policy:
  - Allowed only for production outage.
  - Requires immediate follow-up migration PR that codifies the exact emergency change.
  - Must include postmortem entry with root cause and prevention action.

## Open questions
- Should break-glass actions require two-person approval before execution in production?
- Should service-role edge functions have separate keys/scopes by function class (generate vs submit)?
- Should policy regression checks be required before every production deploy or only schema deploys?

## Next implementation steps
- Add `MIGRATION_GOVERNANCE.md` at repo root or `DataInfra/`:
  - PR checklist for schema/RLS changes.
  - required verification query outputs.
- Add CI policy lint step:
  - verify all in-scope tables have RLS enabled.
  - verify expected policy set exists and no permissive wildcard policy is present.
- Add incident template:
  - fields for symptom, failing layer, SQL/curl evidence, mitigation, permanent fix migration id.
- Add quarterly access review task:
  - confirm no client path uses service-role key.
  - confirm function secrets are scoped and rotated.
