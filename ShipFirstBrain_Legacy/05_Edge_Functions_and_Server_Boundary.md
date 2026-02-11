# Edge Functions and Server Boundary

## Customer-invoked functions
- `generate-docs`
- `submit-run`

## Required auth flow
1. Require bearer JWT in `Authorization` header.
2. Resolve user via Supabase Auth.
3. Require `project_id` and `cycle_no` inputs.
4. Verify project ownership (`projects.owner_user_id == user.id`) before any writes.

## Write boundary
- Client never writes server-only tables directly.
- Functions write:
  - `generation_runs`
  - `contract_versions`
  - `contract_docs`
  - `requirements`
  - `provenance_links`
  - `submission_artifacts`
  - `audit_events`

## Error envelope contract
- Functions return structured errors:
  - `error.code`
  - `error.message`
  - `error.layer` (`auth` / `authorization` / `validation` / `schema` / `transient` / `server`)
  - optional operation/details/hint
- Goal: deterministic client triage by layer and status.

## Security boundaries
- OpenAI key and service role key are server-only secrets.
- iOS receives only Supabase URL and anon key.
- Storage upload uses service role inside `submit-run`; bucket remains private.

## Submit contract
- `submit-run` SHALL fail if role set is not complete (`1..10`).
- Successful submit SHALL produce:
  - storage object path,
  - `submission_artifacts` record,
  - audit event linking submission to contract version.
