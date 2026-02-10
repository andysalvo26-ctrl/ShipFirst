Embeddings Plan

Purpose:
- Improve retrieval quality for evidence recall, contradiction detection support, and personalization continuity.
- Embeddings are assistive only; canonical truth remains in record model and validators.

What gets embedded:
- IntakeTurn normalized text with role and cycle tags.
- ExtractedFact claim text.
- DecisionItem claim and rationale.
- Requirement claim and acceptance criteria text.
- Contradiction summary text.
- Builder Notes bullet text.

What does not get embedded as truth:
- Gate outcomes.
- Commit approvals.
- Status labels as standalone truth.
- AuditEvent control fields.

Retrieval usage by stage:
- Discovery: retrieve semantically similar prior intake turns to avoid duplicate questioning.
- Extraction: retrieve nearby claims for context disambiguation.
- Ambiguity: retrieve potentially conflicting facts and prior similar contradictions.
- Confirmation: retrieve evidence snippets to support user-visible clarification prompts.
- Assembly: retrieve language palette and high-signal phrasing patterns from project-specific prior material.
- Consistency: retrieve semantically close requirements to detect latent duplication and contradictions.
- Commit: no dependency on embeddings for final trust checks.

Retrieval guardrails:
- Provenance-first: retrieved snippets are suggestions until linked via evidence_refs.
- Stage-scoped retrieval: no broad cross-stage retrieval without explicit purpose.
- Cycle-aware retrieval: current cycle first, parent cycles second.

Fallback behavior when embeddings are unavailable:
- Switch to lexical plus metadata retrieval over canonical records.
- Disable embedding-dependent quality enhancements.
- Emit warning-level issue in validation output.
- Never block commit solely due to embedding outage if trust-critical checks pass.

Cost and staleness controls:
- Embed canonicalized text only.
- Re-embed only on meaningful text change.
- Mark stale embeddings when source version changes.
- Keep embedding profile version with each EmbeddingRecord.

OPEN BOUNDARY: embedding scope
- Option A: embed intake, decisions, requirements only.
- Option B: embed all textual records.
- Option C: embed committed artifacts only.
- Recommended default: Option A.
