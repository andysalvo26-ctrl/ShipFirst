# AI Readiness and Embeddings Policy (Phase 1 Canonical)

## Why this exists
Phase 1 uses server-side LLM calls, but it should not pretend advanced retrieval systems are required now. This document keeps future AI expansion disciplined and tenant-safe while preserving current deterministic contracts. It prevents speculative AI scope from displacing current reliability work.

## Phase 1 truth
- Embeddings and vector retrieval are not required for the active intake-to-submit loop.
- Existing generation must remain valid without any embedding subsystem.

## Non-negotiable constraints for future AI additions
1. Retrieval must enforce tenant ownership before ranking.
2. Retrieved context must carry provenance back to source records.
3. Unknown meaning cannot be silently rewritten through retrieval heuristics.
4. Embedding records must include source identity and version marker.

## Minimum entry gate for Embeddings v1
Embeddings may enter scope only after Phase 1 verification gates are consistently green and retrieval behavior can be tested against ownership and provenance constraints.

## Phase 1 non-goals
- No production vector search dependency.
- No autonomous decision synthesis that bypasses confirmation gates.
