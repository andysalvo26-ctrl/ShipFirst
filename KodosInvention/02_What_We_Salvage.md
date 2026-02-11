# What We Salvage
Status: Binding

## Purpose
This document freezes the structural assets that are already correct and must be reused. It prevents rewrite churn in the backend truth plane. It also prevents accidental weakening of security and trust constraints.

## Binding Statements
- Reuse `projects.owner_user_id` ownership root and `user_owns_project(project_id)` authorization predicate.
- Reuse append-only `intake_turns` and immutable `contract_versions` guarantees.
- Reuse trust labels and explicit confirmation linkage (`confirmed_by_turn_id`) as promotion boundary.
- Reuse persisted interview state tables: `artifact_inputs`, `interview_turn_state`, `interview_checkpoints`.
- Reuse website-ingestion record tables: `artifact_ingest_runs`, `artifact_pages`, `artifact_summaries`.
- Reuse verifier gates as mandatory preflight checks before implementation merges.

## Definitions
- Salvage: Existing components that remain normative for Kodos and should not be redesigned.
- Promotion boundary: Rule that inferred meaning cannot become user truth without explicit confirmation linkage.

## Evidence Pointers
- `supabase/migrations/20260210213000_phase1_launch_hardening.sql`
- `supabase/migrations/20260210133000_canonical_brain_schema.sql`
- `supabase/migrations/20260211020000_interview_engine_state_support.sql`
- `supabase/migrations/20260211032000_v3_website_ingestion_state.sql`
- `supabase/migrations/20260211043000_interview_checkpoints.sql`
- `supabase/functions/_shared/interview_gates.ts`
- `scripts/verify_interview_engine_contract.sh`
- `scripts/verify_db_contract.sh`
