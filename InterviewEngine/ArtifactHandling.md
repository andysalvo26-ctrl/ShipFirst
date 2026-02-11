# Artifact Handling

## What Counts as an Artifact
Any externally referenced source the user expects the system to understand before asking decisions, including:
- websites,
- brand pages,
- linked docs,
- uploaded briefs/media,
- existing product copy.

## Required Posture Shift
When an artifact is introduced, the engine must pause directional extraction and enter comprehension verification first.  
The first responsibility is not “ask the next best product question”; it is “prove understanding and invite correction.”

## Required Behavior
1. Ingest artifact context (or mark ingestion failure explicitly).
2. Produce plain-language comprehension summary.
3. Ask for correction/confirmation.
4. Only after confirmation, continue extraction.

## Partial or Unreliable Ingestion Rule
If ingestion is partial, uncertain, or failed:
- uncertainty must be explicit,
- directional narrowing must be delayed,
- user may supply correction text directly.

No hidden confidence is allowed.

## Internal Risks to Monitor
- Anchoring risk: system overcommits to website narrative and suppresses new intent.
- Shallow confirmation risk: user says “yes” to move forward despite missing nuance.
- Hallucinated context risk: system attributes details not present in artifact.

## Control Rule
Artifact-grounding exits only when one of the following is true:
- user confirms interpretation,
- user corrects interpretation and correction is acknowledged,
- user explicitly chooses to proceed with unresolved artifact uncertainty.
