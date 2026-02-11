# ShipFirstPlatform Frozen Truth

Purpose:
- This folder is the canonical, reviewable contract for ShipFirst Phase 1 platform behavior.
- It defines what is implemented, what is enforced, and what is intentionally out of scope.

Scope:
- Single customer-facing intake app.
- Supabase-backed control plane.
- Server-side generation and submission flows.

How to use this folder:
1. Read `01_Platform_Definition.md` for top-level contract.
2. Read `03_Identity_Ownership_RLS.md` before any schema/RLS change.
3. Read `06_Verification_and_Drift_Prevention.md` before merge/deploy.
4. Treat these files as implementation gates: changes to schema/auth/policies/functions must update this folder in the same PR.

Implemented vs intended language:
- "Implemented via X" means code/migration/script exists in this repo.
- "Phase gate" means required before advancing product scope.

Relationship to `DataInfra/`:
- `DataInfra/` is planning and operating guidance.
- `ShipFirstPlatform/` is frozen contract language for current platform truth.
