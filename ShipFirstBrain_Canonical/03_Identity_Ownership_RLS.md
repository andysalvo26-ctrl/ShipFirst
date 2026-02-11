# Identity, Ownership, and RLS (Phase 1 Canonical)

## Why this exists
Without a single ownership model, trust breaks under load and drift. This document defines who owns what and how that ownership is enforced in data access. It is written so operators and engineers can both verify the same boundary behavior.

## Phase 1 ownership model
- Canonical tenant key in Phase 1: `projects.owner_user_id`.
- Canonical run key: `(project_id, cycle_no)`.
- Canonical ownership predicate: `user_owns_project(project_id)`.
- No implicit ownership through undocumented joins.

## Creation and propagation rules
- Project creation sets ownership from authenticated user context.
- Customer-path records must carry `project_id`.
- Project-scoped table access is always evaluated through project ownership.

## Per-table ownership and access contract

| Table | Ownership Column / Link | Client Write | Client Read | Plane |
|---|---|---|---|---|
| `projects` | `owner_user_id` | own insert/update only | own select only | Control |
| `intake_turns` | `project_id` -> `projects.id` | insert | select | Control |
| `decision_items` | `project_id` -> `projects.id` | insert/update | select | Control |
| `generation_runs` | `project_id` -> `projects.id` | none | select | Control |
| `contract_versions` | `project_id` -> `projects.id` | none | select | Control |
| `contract_docs` | `project_id` -> `projects.id` | none | select | Control |
| `requirements` | `project_id` -> `projects.id` | none | select | Control |
| `provenance_links` | `project_id` -> `projects.id` | none | select | Control |
| `submission_artifacts` | `project_id` -> `projects.id` | none | select | Control |
| `audit_events` | `project_id` -> `projects.id` | none | select | Control |

## Non-negotiable security boundaries
- Supabase anon key is client-safe; service role is server-only.
- Edge Functions validate caller JWT and ownership before writes.
- RLS remains enabled on all customer-path tables.
