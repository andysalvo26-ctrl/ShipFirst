# AI Readiness and Embeddings Policy (Phase-Gated)

## Current truth
- Phase 1 does not require embeddings to satisfy intake, generation, and submission contracts.
- LLM generation is already server-side and gated by deterministic validation.

## Tenant-safe retrieval rules
1. Any future retrieval query SHALL apply tenant ownership filtering before ranking.
2. Retrieval outputs SHALL include source references that map back to control-plane records.
3. Cross-tenant retrieval is prohibited.

## Provenance and determinism constraints
- Embeddings (when added) SHALL be derived from explicit source records:
  - intake turns,
  - decision items,
  - requirements or scoped contract content.
- Embedding records SHALL store:
  - source table,
  - source row id,
  - source hash/version marker,
  - embedding model/version metadata.
- Source updates SHALL mark prior embeddings stale; no silent rewrite.

## Phase gate for embeddings
Embeddings can enter scope only after:
1. schema/RLS verification gates are stable,
2. retrieval ownership checks are testable,
3. provenance linkage is preserved in retrieval results.

## Non-goals (Phase 1)
- No vector search in production customer path.
- No autonomous decision synthesis that bypasses trust labels and confirmations.
