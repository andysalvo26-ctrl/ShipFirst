# Public Signal Extraction (Factual Only)

These claims are derivable from implemented contracts and are safe for external-facing summaries if phrased accurately.

1. Tenant isolation is enforced at the data access layer using row-level policies.
2. Customer ownership is validated before server-side generation and submission writes.
3. The intake workflow enforces a fixed 10-document output contract.
4. Contract claims are labeled with explicit trust states (`USER_SAID`, `ASSUMED`, `UNKNOWN`).
5. Requirement claims are linked back to source evidence through provenance pointers.
6. Contract versions are immutable once committed.
7. Privileged actions are expected to be auditable and scoped.
8. Client apps do not include model-provider secrets.
9. Submission artifacts are stored in a private bucket with tracked storage paths.
10. Schema and policy drift checks are codified in repository verification tooling.
11. Error handling distinguishes auth, authorization, validation, schema, and transient layers in server responses.
