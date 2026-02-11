# DataInfra

Purpose:
- Define the minimum actionable data-infrastructure meta-plan for ShipFirst’s current product scope: one iOS intake app, Supabase/Postgres, and server-side generation/submit flows.
- Prevent the drift pattern already seen in production (missing columns, broken RLS assumptions, policy/schema mismatch).

Non-goals:
- No new product surfaces.
- No stack migration away from Supabase + Postgres + Edge Functions.
- No speculative distributed-systems design that is not needed for current growth stage.

Read order:
1. `01_Canonical_Data_Contract.md`
2. `02_Domain_Model_and_Lifecycle.md`
3. `03_Runtime_Observability_and_Verification.md`
4. `04_AI_Embeddings_Readiness.md`
5. `05_Security_and_Governance.md`

How this folder should be used:
- Treat these docs as implementation guidance and review criteria, not aspirational prose.
- Each doc includes next steps that can be ticketed and checked.
- Changes to schema/RLS/runtime behavior should update these docs in the same PR.
