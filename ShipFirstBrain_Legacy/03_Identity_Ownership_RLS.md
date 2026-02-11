# Identity, Ownership, and RLS Contract

## Phase 1 tenant identity
- Canonical tenant key: `projects.owner_user_id`.
- Ownership lookup function: `public.user_owns_project(project_id uuid) -> boolean`.
- No alternate ownership path is allowed for customer-path tables.

## Project creation ownership rule
- Client inserts only `name` into `projects`.
- DB default sets `owner_user_id = auth.uid()`.
- Trigger enforces:
  - insert spoofing blocked (`owner_user_id` cannot differ from `auth.uid()` for authenticated inserts),
  - ownership immutability on updates.
- RLS policies enforce owner-scoped select/insert/update on `projects`.

## Mandatory invariant
- Every customer-path control-plane table SHALL include:
  - `project_id uuid not null`,
  - FK to `projects(id)`.

## RLS matrix (Phase 1)

| Table | Ownership Check | Client Write | Client Read |
|---|---|---|---|
| `projects` | `owner_user_id = auth.uid()` | insert, update own | select own |
| `intake_turns` | `user_owns_project(project_id)` | insert | select |
| `decision_items` | `user_owns_project(project_id)` | insert, update | select |
| `generation_runs` | `user_owns_project(project_id)` | none | select |
| `contract_versions` | `user_owns_project(project_id)` | none | select |
| `contract_docs` | `user_owns_project(project_id)` | none | select |
| `requirements` | `user_owns_project(project_id)` | none | select |
| `provenance_links` | `user_owns_project(project_id)` | none | select |
| `submission_artifacts` | `user_owns_project(project_id)` | none | select |
| `audit_events` | `user_owns_project(project_id)` | none | select |

## Server-role boundary
- Service role is allowed only in Edge Functions.
- Service-role logic SHALL validate caller JWT and `project_id` ownership before writes.
- Service role SHALL NOT be used in iOS client.

## Policy lifecycle
- Policies are managed only through migrations.
- Conflicting policies are dropped and recreated by canonical hardening migration.
- Policy existence is asserted by `scripts/verify_db_contract.sh`.
