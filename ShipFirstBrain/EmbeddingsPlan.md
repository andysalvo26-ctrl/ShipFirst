# Embeddings Plan

Purpose:
- Improve retrieval quality for evidence recall, contradiction discovery support, and language personalization continuity.
- Keep canonical truth in primary records and validators.

## Embed sources
- IntakeTurn normalized text and tags.
- ExtractedFact claims.
- DecisionItem claims and rationale.
- Requirement claims and acceptance text.
- Contradiction summaries.
- Builder Notes bullets.

## Do not treat as canonical truth
- Gate pass/fail outcomes.
- Commit approvals.
- Status labels without source lineage.
- Control metadata from audit events.

## Retrieval by stage
- Discovery: find near-duplicate prior prompts and missing-context cues.
- Extraction: pull adjacent semantic evidence for claim disambiguation.
- Ambiguity: surface potential conflicts and similar unresolved patterns.
- Confirmation: show concise evidence snippets behind MCQ and clarification prompts.
- Assembly: apply project language palette and avoid repetitive phrasing.
- Consistency: detect semantic duplicates and latent conflict patterns.
- Commit: no trust-critical dependency on embeddings.

## Retrieval guardrails
- Provenance-first usage: retrieval suggests, validators decide.
- Stage-scoped queries only.
- Cycle-aware retrieval order: current cycle, then parent lineage.

## Fallback behavior
If embeddings are unavailable:
- Use lexical plus metadata retrieval over canonical records.
- Disable embedding-only enhancements.
- Emit `RetrievalIssue` warning.
- Continue only if trust-critical gates still pass.

## Cost and staleness
- Embed canonicalized text only.
- Re-embed on meaningful source change.
- Mark stale vectors when source version advances.
- Track embedding profile version per record.

OPEN BOUNDARY: embedding coverage
- Option A: intake, decisions, requirements.
- Option B: all textual artifacts.
- Option C: committed artifacts only.
- Recommended default: Option A.
