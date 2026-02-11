# Platform Definition (Phase 1 Frozen)

## Purpose
ShipFirst Phase 1 is a managed intake platform that captures customer intent, enforces explicit alignment, and produces an immutable 10-document contract packet. The platform is not a customer-managed hosting stack, not an app builder runtime, and not an unconstrained no-code system. Customer meaning capture and review are in scope; runtime app operations and code generation are not.

## Surfaces (agreed set)
- Intake Surface (customer-facing, in scope now).
- Customer Console (future phase).
- Runtime Apps (future phase).
- Dev Central (internal, minimal operational scope in phase 1).
- ShipFirst Website (public discovery/onboarding).

## Canonical identity
- Phase 1 tenant key is `projects.owner_user_id`.
- Canonical run identity is `(project_id, cycle_no)`.
- Contract identity is `contract_version_id`.
- Submission identity is `submission_id` and storage path.

## Platform laws
1. Every customer-path control-plane table SHALL carry `project_id`.
2. Ownership SHALL be resolved through one predicate: `user_owns_project(project_id)`.
3. Intake outputs MUST contain exactly 10 docs with role IDs `1..10`.
4. Generation and submit gates MUST enforce the exactly-10 invariant server-side.
5. Every requirement claim MUST include trust label (`USER_SAID` / `ASSUMED` / `UNKNOWN`) and provenance pointers.
6. Unknown meaning MUST NOT be silently upgraded to certainty.
7. Contract versions SHALL be immutable after commit.
8. LLM calls SHALL run server-side only; client MUST NOT contain provider secrets.
9. Customer-invoked Edge Functions MUST require JWT + ownership check before writes.
10. RLS SHALL be enabled and fail closed for all customer-path tables.

## Control-plane boundary
- Client writable: `projects`, `intake_turns`, `decision_items`.
- Server writable: `generation_runs`, `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `submission_artifacts`, `audit_events`.

## Implemented verification gates
- Implemented gate 1: migration-enforced schema and policy hardening.
- Implemented gate 2: `scripts/verify_db_contract.sh` contract assertions.
- Implemented gate 3: `VERIFY.md` smoke test sequence.
- Implemented gate 4: CI stub at `.github/workflows/verify-db-contract.yml`.

## Phase 1 explicit exclusions
- No customer runtime console features.
- No deployment automation from docs to app.
- No org-level multi-tenant abstraction beyond `owner_user_id`.
- No cross-tenant retrieval/search.
