# AI Readiness (Embeddings / Retrieval) Plan

## Purpose
- Define where embeddings fit in ShipFirst’s current architecture without destabilizing deterministic contract generation.
- Ensure any retrieval system remains tenant-safe, provenance-preserving, and optional.

## Non-goals
- No immediate rollout of embeddings in current release path.
- No autonomous decisioning from vectors without explicit trust/provenance rules.

## Decisions / Invariants
- Embeddings are additive and asynchronous:
  - Generation and submit flows must work even if embeddings are disabled or delayed.
- Candidate embedding sources (priority order):
  - `intake_turns.raw_text` (high signal for user intent history).
  - `decision_items.claim` + status/evidence refs (alignment state).
  - `requirements.requirement_text` and selected `contract_docs.body` segments (contract retrieval).
- Do not embed:
  - transient auth/session data
  - secrets/config
  - opaque large blobs that cannot be traced back to source rows.
- Provenance invariant:
  - Every embedding row must store source table, source row id, source version marker, and source hash/fingerprint.
  - If source changes, old embedding is marked stale and re-embedded; no silent replacement.
- Tenant isolation invariant:
  - Retrieval queries must enforce owner/tenant filtering before similarity ranking.
  - Cross-tenant retrieval is a hard fail.
- Storage decision for v1-ready path:
  - Keep vectors in Postgres (`pgvector`) if row counts and latency targets remain acceptable.
  - Re-evaluate external vector store only when measured scale requires it.

## Open questions
- Chunking strategy for `contract_docs.body`:
  - whole-doc embeddings vs section-level chunks aligned to required doc spine.
- Freshness SLA:
  - near-real-time indexing after each commit vs batched async indexing.
- Model/version governance:
  - how often embedding model/version can change before retrieval behavior drift becomes unacceptable.

## Next implementation steps
- Add an `embeddings_v1` design artifact (no migration yet) defining:
  - source_ref fields, tenant keys, vector dimension placeholder, model_version, source_hash, stale flag, timestamps.
- Add retrieval safety checklist:
  - query must include tenant filter predicate before similarity sort.
  - result payload must include source_ref and trust/provenance context.
- Add a background job contract for embedding sync:
  - trigger on intake turn insert, decision update, contract version commit.
  - idempotent upsert keyed by source_ref + source_hash + model_version.
- Define measurable go/no-go criteria for enabling embeddings in production (latency, recall utility, cost).
