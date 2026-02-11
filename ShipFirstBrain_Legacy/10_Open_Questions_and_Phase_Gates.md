# Open Questions and Phase Gates

## Open questions
1. When should Phase 2 introduce org-level `tenant_id` separate from `owner_user_id`?
2. What migration strategy preserves backward compatibility for existing `project_id + cycle_no` contracts when identity broadens?
3. Which exact Phase 2 capabilities move Customer Console from out-of-scope to in-scope?
4. What SLOs should be formalized for generate and submit operations?
5. What retention and archival policy should apply to intake turns, audit events, and submission artifacts?
6. What break-glass approval workflow is required by incident severity?
7. What minimum observability fields should be mandatory in all edge responses and audit records?
8. What CI environment standard should enforce database contract checks on every PR?
9. What measurable criteria are required before embeddings/retrieval can be enabled?

## Phase 1 gate checklist
- Ownership root is `projects.owner_user_id`.
- Ownership predicate `user_owns_project(project_id)` exists and is used by project-scoped policies.
- Every customer-path control-plane table has non-null `project_id` with FK to `projects`.
- `decision_items` and `contract_versions` schema match client/function expectations.
- Exactly-10 server-side gates are active for generate and submit.
- `VERIFY.md` and `scripts/verify_db_contract.sh` pass in target environment.

## Phase 2 entry gate (must pass before expansion)
1. CI-backed DB contract checks are enforced for all merges.
2. Incident and break-glass logging process is in active use.
3. Runtime app data-plane contracts are documented with explicit ownership and RLS model.
4. Customer Console scope is defined with bounded write capabilities and policy coverage.
