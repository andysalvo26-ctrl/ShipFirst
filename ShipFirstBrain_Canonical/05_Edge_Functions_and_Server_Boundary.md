# Edge Functions and Server Boundary (Phase 1 Canonical)

## Why this exists
The intake app must feel simple to users while still enforcing trust and security rules. This document defines the smallest server boundary required to keep meaning capture deterministic and auditable. It makes clear which actions happen in the client versus in trusted server code.

## Active functions in Phase 1
- `generate-docs`: validates run state and produces/retrieves a contract version with role docs.
- `submit-run`: re-validates contract completeness, creates bundle manifest, uploads zip, and records submission metadata.

## Authentication and authorization flow
1. Client sends bearer JWT to Edge Function.
2. Function resolves authenticated user.
3. Function verifies ownership of `project_id`.
4. Function proceeds only if ownership and gates pass.

## Write boundary
- Client-writable tables stay limited to intake and explicit decision capture.
- Server-only writes include generation logs, contract versions/docs, requirements/provenance, submission artifacts, and audit records.
- Provider secrets and service role keys remain server-side only.

## Deterministic gate expectations
- Generation must fail if exactly-10 contract conditions are not satisfied.
- Submit must fail if role set, trust/provenance requirements, or ownership checks fail.
- Unknown claims must remain explicit; functions must not silently rewrite them to certainty.

## Error contract
Server responses should distinguish layer (`auth`, `authorization`, `validation`, `schema`, `transient`, `server`) so operators can diagnose quickly without mislabeling every failure as user session error.
