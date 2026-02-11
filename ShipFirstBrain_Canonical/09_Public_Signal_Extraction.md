# Public Signal Extraction (Phase 1 Canonical)

## Why this exists
ShipFirst needs externally understandable claims, but those claims must remain truthful to what is actually shipped. This document defines the factual signals that are safe to reuse in customer or investor communication. It avoids hype by anchoring every signal to implemented Phase 1 behavior.

## Safe external signals (Phase 1)
1. One customer-facing intake app is live in Phase 1.
2. Runs must produce exactly ten validated role documents before submit.
3. Claims include explicit trust labels and provenance pointers.
4. Unknown meaning is preserved until explicit confirmation.
5. All model calls happen server-side; secrets are not embedded in client apps.
6. Ownership is enforced at data access boundaries with RLS and ownership checks.
7. Submission creates a private bundle artifact and tracked metadata record.
8. Schema/policy contract checks are codified in repository verification tooling.

## Signals to avoid in Phase 1
- Claims that customers can already operate live runtime apps via a console.
- Claims that ShipFirst automatically builds and deploys apps from the contract packet.
- Claims that embeddings/vector systems are active in core customer path.

## Update rule
If a claim is not backed by migration, code, and verification evidence, it is not a valid external signal.
