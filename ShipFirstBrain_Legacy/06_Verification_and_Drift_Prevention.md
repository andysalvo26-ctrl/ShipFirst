# Verification and Drift Prevention

## Implemented gates
- Gate A (schema/policy contract): `scripts/verify_db_contract.sh`
- Gate B (runtime smoke): `VERIFY.md` end-to-end sequence
- Gate C (CI stub): `.github/workflows/verify-db-contract.yml`

## What Gate A asserts
- Required tables exist.
- Required columns exist (`owner_user_id`, `project_id`, `decision_items` canonical fields, `version_number`).
- RLS enabled on all customer-path control-plane tables.
- Required policy set exists.
- `public.user_owns_project(uuid)` exists.

## What Gate B asserts
Flow:
1. sign in user
2. create project
3. insert intake turns
4. upsert decision item
5. call `generate-docs` and verify 10 docs
6. call `submit-run` and verify storage path + submission row

Expected:
- No undefined_column errors.
- No project insert RLS denial for authenticated owner.
- No silent fallback to missing role sets.

## Drift prevention operating rules
1. No schema edits outside migration files.
2. No policy edits outside migration files.
3. Any new query in iOS or Edge that touches DB columns MUST be accompanied by schema verification updates.
4. If Gate A fails, deployment SHOULD be blocked until fixed.

## Current limitation
- CI gate requires `DATABASE_URL` secret configuration.
- Until CI secret is configured, Gate A is available locally and in release checklists but not guaranteed in remote CI.
