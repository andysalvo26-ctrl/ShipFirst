# Verification and Drift Prevention (Phase 1 Canonical)

## Why this exists
Phase 1 can only enable future owner-ops if its core contracts remain stable under real usage. This document defines the minimum verification flow that catches schema, RLS, and boundary drift before it harms users. It focuses on deterministic checks, not perfect tooling.

## Verification layers
- Contract check script: validates required tables, columns, policies, and ownership function.
- Run smoke flow: verifies sign-in, run creation, intake writes, generation, review, and submit handoff.
- Build/test check: confirms intake app still compiles and core model invariants hold.

## Implemented checks in repo
- `scripts/verify_db_contract.sh` (authoritative DB contract assertions via `psql`).
- `VERIFY.md` (end-to-end smoke flow for Phase 1 path).
- Optional CI stub for DB contract checks when environment secrets are configured.

## Drift prevention rules
1. Schema and policy changes only through migrations.
2. New client or function queries must map to verified columns before merge.
3. Any violation of exactly-10 or trust/provenance invariants blocks release.
4. Optional tooling failures (for example Docker-dependent diff helpers) must not bypass required contract checks.

## Phase 1 pass condition
Phase 1 verification is considered green only when ownership enforcement, exactly-10 generation, user review path, and submit artifact recording all pass together.
