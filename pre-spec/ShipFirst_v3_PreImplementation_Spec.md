# ShipFirst v3 Pre-Implementation Spec

Status: Binding pre-specification for implementation planning only (no code changes in this run)

Scope guard: This document covers the existing Phase 1 Intake Surface and the minimum constrained inventions required for v3 behavior; it does not authorize new product surfaces.

---

## 1) Executive Summary

### EXISTING
ShipFirst currently runs a real Phase 1 path: one iOS intake app, Supabase Auth/RLS data boundary, server-side edge functions, and a contract packet flow that enforces exactly 10 documents at commit time. The repo already contains strict ownership controls (`projects.owner_user_id`, `user_owns_project(project_id)`), trust labels, provenance links, and submission artifacts in private storage. The major problem is not missing infrastructure but drift between documents and runtime semantics (especially commit vs submit lifecycle and endpoint framing). Evidence: `ALIGNMENT_REPORT.md`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`, `supabase/functions/next-turn/index.ts`, `supabase/functions/commit-contract/index.ts`, `supabase/migrations/20260210133000_canonical_brain_schema.sql`.

### PROPOSED
ShipFirst v3 is the same Phase 1 product boundary with a stricter interview engine contract: artifact-first grounding, controlled epistemic pace, no silent assumption promotion, and commit-time exactly-10 generation only after readiness is earned. The core unlock is server-side website ingestion as a first-class capability that reduces user burden and improves interviewer faithfulness without introducing new surfaces. Supabase remains the long-term system-of-record for all durable state required by intake, governance, replay, and future surfaces.

---

## 2) Current-State Reality (Evidence-Based)

### EXISTING
What exists and is wired now:
- iOS intake runtime with auth, runs list, chat-like turns, alignment options, commit action, and review list. Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`.
- Info.plist build-setting config boundary for Supabase URL/anon key. Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Info.plist`, `Config/Supabase.xcconfig`.
- Edge functions present: `next-turn`, `commit-contract`, `generate-docs`, `submit-run`. Evidence: `supabase/functions/*/index.ts`.
- Shared explicit confirmation gate for business type. Evidence: `supabase/functions/_shared/interview_gates.ts`.
- Canonical schema + hardening + interview state support are already migrated in repo. Evidence: `supabase/migrations/20260210133000_canonical_brain_schema.sql`, `20260210213000_phase1_launch_hardening.sql`, `20260211020000_interview_engine_state_support.sql`.
- Verification scripts and CI DB contract check exist. Evidence: `scripts/verify_interview_engine_contract.sh`, `scripts/verify_db_contract.sh`, `.github/workflows/verify-db-contract.yml`.

Observed drift points (repo-evidenced):
- Canon authority is fragmented across `ShipFirstBrain_Canonical`, `ShipFirstBrain`, and `ShipFirstPlatform`. Evidence: `ShipFirstBrain/README.md`, `ShipFirstBrain_Canonical/01_Platform_Definition.md`, `ShipFirstPlatform/00_README.md`.
- Canon docs state review-before-submit, but runtime `commit-contract` also bundles/uploads submission artifacts. Evidence: `ShipFirstBrain_Canonical/01_Platform_Definition.md`, `supabase/functions/commit-contract/index.ts`.
- Artifact-first behavior is partially represented server-side (`artifact_inputs`, mode shift), but full website ingestion pipeline is not implemented. Evidence: `supabase/functions/next-turn/index.ts`, `supabase/migrations/20260211020000_interview_engine_state_support.sql`.

UNKNOWN:
- Remote deployed parity (schema/functions/policies) cannot be proven from repository alone in this run.

### PROPOSED
Treat the current runtime as baseline and resolve drift before broad changes:
1. Freeze canon precedence.
2. Freeze one lifecycle truth (commit vs submit boundary).
3. Add website ingestion as first-class server behavior with explicit ingest/verification states.
4. Keep all Phase 1 surface boundaries unchanged.

---

## 3) Canon & Scope Decisions (LOCKED)

### EXISTING
The repo contains multiple “frozen/canonical” claims that are not fully reconciled:
- `ShipFirstBrain_Canonical/*` frames Phase 1 canonical intent.
- `ShipFirstBrain/README.md` claims frozen authoritative truth for that folder.
- `ShipFirstPlatform/00_README.md` claims canonical platform docs but references files that are not present.

### PROPOSED (LOCKED)
The following decisions govern implementation planning:

1. **Canon precedence order (final):**
   - `CANON_PRECEDENCE.md` (if present) is the tie-breaker authority.
   - `ShipFirstBrain_Canonical/*` is the primary intended-truth source for Phase 1 intake behavior and contracts.
   - `InterviewEngine/*` defines posture/move behavior where not in conflict with the Phase 1 canonical docs.
   - Runtime code/schema/scripts are evidence of what exists today, not authority over intended behavior.
   - `ALIGNMENT_REPORT.md` is evidence and context, not a behavioral authority document.
   - `ShipFirstPlatform/*` is informational until fully populated with the intended canonical set.
   - legacy folders are non-authoritative.
   - TODO (required before implementation begins): create `CANON_PRECEDENCE.md` at repo root to formalize and freeze this order.

2. **Phase 1 lifecycle truth (final):**
   - Review-before-submit is canonical behavior.
   - Commit produces and validates exactly-10 contract state.
   - Submit creates bundle+manifest in storage and records artifact metadata.
   - Any current code path that combines commit+submit is drift and must be corrected in implementation.

3. **Artifact ingestion requirement (final):**
   - Artifact ingestion (website/brand pages) is mandatory in v3 Phase 1 behavior.
   - With artifact present, comprehension verification happens before directional narrowing.

4. **Trust-label promotion policy (final):**
   - Durable labels: `USER_SAID`, `ASSUMED`, `UNKNOWN`.
   - `HYPOTHESIZED` is a contract alias to `ASSUMED` only.
   - Promotion to `USER_SAID` requires explicit user confirmation linkage (`confirmed_by_turn_id`).

5. **Scope lock (final):**
   - One customer-facing iOS intake surface only.
   - No runtime owner console, no multi-surface suite additions, no app-generation automation.

---

## 4) Supabase as Long-Term Data Plane (Design Commitments)

### EXISTING
Supabase already operates as the shared data/auth/storage boundary:
- Auth: JWT from client; provider/service secrets server-only.
- Data: project/cycle model with ownership and provenance-oriented tables.
- Storage: private bundle storage in `shipfirst-submissions`.
- Isolation: RLS with `user_owns_project(project_id)` and strict select/write boundaries.

### PROPOSED
Supabase is explicitly committed as durable multi-surface system-of-record with these non-negotiable commitments:

1. **If it matters, it is persisted:**
   Trust-critical state (claims, confirmations, unknowns, contradictions, artifact verification, gate outcomes) SHALL live in Supabase, not only app memory.

2. **State ownership split:**
   - Database owns durable truth, replay metadata, and policy enforcement.
   - App owns presentation and local interaction convenience only.

3. **Event/state discipline:**
   - Append/event tables for chronology and replay.
   - State/snapshot tables for current semantic position and immutable commits.

4. **Immutability + replayability:**
   - `intake_turns` remains append-only.
   - committed contract versions remain immutable.
   - transitions must be reconstructable from DB records and audit trails.

5. **Versioning contract:**
   - Schema version: migration chain.
   - Behavioral contract version: `SHIPFIRST_BRAIN_VERSION` plus function/version tuple metadata.
   - API contracts evolve additively to preserve iOS compatibility.

6. **Future-surface reuse:**
   New surfaces SHALL consume the same project/cycle/contract/provenance records; no forked “surface-local truth” stores.

UNKNOWN:
- Long-term archival and cold-storage policy thresholds are not yet fixed in repo canon.

---

## 5) System Architecture — EXISTING vs PROPOSED

### EXISTING
**iOS app responsibilities now:**
- Auth/session, run list, chat turns, option-chip interactions, commit action, and read-only doc review.
- Calls `next-turn` and `commit-contract` directly; `generate-docs`/`submit-run` methods still exist in service layer.

**Server responsibilities now:**
- `next-turn`: appends turns, updates decisions, returns next assistant prompt/options plus readiness hints.
- `commit-contract`: strict validation + generation + contract writes + currently submission bundle creation.
- `submit-run` and `generate-docs`: operational but not primary iOS path.

**DB responsibilities now:**
- ownership and RLS enforcement,
- trust/provenance representation,
- immutable commit snapshots,
- submission artifact metadata.

### PROPOSED
Architecture is refined, not rebuilt:

1. **Interview loop boundary remains `next-turn`:**
   This endpoint becomes the only interactive interviewer loop unit.

2. **Commit and submit semantics are separated by behavior contract:**
   Commit = validate/materialize exactly-10 packet.
   Submit = explicit handoff bundle creation after review intent.

3. **Website ingestion is integrated into the same engine boundary:**
   Ingestion + verification state is persisted and fed into turn planning.

4. **DB remains control backbone:**
   Posture/move/burden/pace, artifact verification, and trust transitions are representable and replayable.

5. **No surface expansion:**
   iOS remains the single customer-facing intake surface for Phase 1.

---

## 6) Website Ingestion & “Browsing” Design (Deep Dive)

### EXISTING
- Artifact representation exists (`artifact_inputs`) with `ingest_state`, `verification_state`, and summary text.
- `next-turn` can switch to artifact-grounding prompts when artifact_ref is supplied.
- Full website fetch/extract/crawl pipeline is not implemented as durable DB-first lifecycle.

### PROPOSED
#### 6.1 Lifecycle state machine (DB-first)
Website ingestion is modeled as deterministic, auditable server workflow:
1. `pending` (artifact registered)
2. `fetching` (server fetch in progress)
3. `partial` (some content extracted, confidence incomplete)
4. `complete` (bounded extraction completed)
5. `failed` (no reliable extractable content)

Verification state remains separate and required:
- `unverified` -> `user_confirmed` or `user_corrected`
- Directional narrowing is forbidden while `verification_state=unverified` for artifact-led sessions.

#### 6.2 Data model (described; additive)
Keep existing `artifact_inputs`, add minimal supporting records for replay:

1) `artifact_ingest_runs` (append-only)
- Project/cycle keyed attempt records
- stores timing, status, HTTP result class, fetch limits hit, error code, fingerprint

2) `artifact_pages` (append-only)
- Page-level fetch/extract outputs
- URL/canonical URL/depth/content type/hash/storage refs

3) `artifact_summaries` (versioned)
- Human-readable interpretation snapshots used in verification prompts
- includes source page refs and confidence metadata

All new records SHALL include `project_id` and remain under `user_owns_project(project_id)` RLS semantics.

#### 6.3 Safe server-side fetch/extract contract
Phase 1 bounded behavior:
- HTTPS only
- strict timeout limits
- redirect cap
- same-origin page cap
- byte caps per page and per run
- content type allowlist (`text/html`, optional `text/plain`)
- deny localhost/internal/private network targets
- no JS execution, no authenticated crawling, no paywall bypass

If limits are hit, state is `partial` or `failed`; it is never silently treated as complete.

#### 6.4 Storage strategy
Use private buckets for ingestion traces:
- raw fetch snapshots (optional, bounded)
- normalized extracted text artifacts

Path convention SHALL include user/project/cycle/artifact/run identity to preserve replay and operator auditability.

#### 6.5 Provenance and trust propagation
- Artifact-derived claims default to `ASSUMED` (or alias `HYPOTHESIZED` in contract layer).
- Promotion to `USER_SAID` requires explicit confirmation event linkage (`confirmed_by_turn_id`).
- Provenance links include artifact page/summary references and turn/decision references where applicable.

#### 6.6 Binding Invariants for Website Ingestion & Browsing (LOCKED)
The following are binding invariants and non-negotiable:
- The LLM SHALL only summarize or answer about a website using content fetched/extracted and stored in Supabase for the current run, with provenance.
- The assistant SHALL NOT claim it “visited” or “read” a site unless `ingest_state` is `partial` or `complete` and there are stored extracted-content/page references for that run.
- If ingestion is `partial` or `failed`, the assistant SHALL explicitly state that condition and SHALL either ask for user-provided text or ask the user to narrow to specific pages/sections.
- Every ingestion-derived claim SHALL be traceable to internal provenance pointers (hashes/ids), even if those pointers are not displayed to the user.

#### 6.7 Partial/failed ingestion behavior
Server response SHALL include:
- what was captured,
- what is uncertain,
- one low-burden next clarification path.

Conversation continues; only commit is blocked by unresolved critical unknowns.

#### 6.8 Phase 1 Ingestion Execution Model (LOCKED)
- Phase 1 ingestion is synchronous MVP behavior within strict request limits.
- Async queue/background ingestion is explicitly Phase 2 (optional), not Phase 1.
- On timeout/limit failures, the server SHALL mark ingestion `partial` or `failed` immediately and return a verification/correction prompt; it SHALL NOT silently continue as if ingestion succeeded.

#### 6.9 Ingestion Idempotency and Replay Rule (LOCKED)
- Every ingestion run SHALL use a deterministic idempotency key:
  `idempotency_key = hash(project_id, cycle_no, canonical_url, ingestion_limits_version, brain_version)`.
- Repeated ingestion requests with the same idempotency key SHALL reuse the prior run result unless `force_refresh=true`.
- This idempotency rule is required for deterministic replay, auditability, and drift-resistant behavior.

#### 6.10 Explicit cannot-do cases (Phase 1)
Not supported in v3 Phase 1 ingestion:
- JS-rendered-only websites requiring browser execution
- authenticated/private pages and paywalled content
- anti-bot challenge-protected pages
- extremely large sites beyond configured limits

UNKNOWN:
- Exact fetch limits should be tuned from observed function runtime metrics; defaults must be conservative initially.

---

## 7) Drift-Prevention Mechanisms

### EXISTING
- Structural DB verifier exists (`verify_db_contract.sh`).
- Behavior-contract verifier exists (`verify_interview_engine_contract.sh`).
- CI workflow runs DB verifier with configured secret.

### PROPOSED
1. **Behavior gates become release-critical:**
   Verification SHALL assert not only schema/RLS presence but trust-behavior laws (artifact-first ordering, explicit confirmation linkage, no silent promotion).

2. **Canonical precedence declaration enforcement:**
   Any contract-changing PR SHALL include doc updates in canonical folders and pass behavior verifiers.

3. **Drift-safe endpoint contract checks:**
   Add key-response field assertions (`posture_mode`, `move_type`, unresolved pointers, commit blockers) for interactive endpoints.

4. **Migration hygiene:**
   Additive migrations only unless deprecation plan is documented and approved.

5. **Human review gates:**
   Trust-boundary changes require explicit reviewer acknowledgment (no silent meaning laundering, UNKNOWN durability maintained).

UNKNOWN:
- CI depth beyond current single DB verifier job is not yet standardized in repo canon.

---

## 8) Salvage / Rewrite / Deprecate Matrix

### EXISTING
Major components are usable but not uniformly aligned to the locked lifecycle and artifact behavior.

### PROPOSED

| Component | Current State | Decision | Why | Trust Constraint |
|---|---|---|---|---|
| `next-turn` | Active interview loop endpoint | Modify | Keep as primary loop; add full artifact ingestion orchestration and strict trust-state transitions | No inferred claim becomes USER_SAID without explicit confirmation linkage |
| `commit-contract` | Active strict gate + generation + currently submission side effects | Modify | Keep strict exactly-10 commit; remove implicit final submit behavior | Commit must not finalize handoff artifact without explicit submit action |
| `submit-run` | Active submission bundle endpoint | Keep (tighten) | Use as explicit post-review handoff boundary | Ownership + contract version checks remain mandatory |
| `generate-docs` | Legacy parallel generation path | Quarantine/Deprecate | Avoid dual contract paths and lifecycle drift | Must not be reintroduced as primary path |
| iOS intake screens | Functional chat/review | Modify | Preserve single surface while adding artifact input and lifecycle-accurate actions | No second customer surface, no runtime console |
| Shared trust/gate helpers | Present and useful | Keep/extend | Centralize predicates to avoid endpoint drift | One canonical confirmation predicate shared across endpoints |
| Core schema tables | Mature baseline | Keep | Ownership/provenance foundations are correct | Additive-only schema evolution |
| `artifact_inputs`, `interview_turn_state` | Present but underused | Extend | Needed for full replayable ingestion + posture tracking | Project-scoped RLS only |
| Verification scripts | Present and passing locally | Extend | Add behavior-law coverage for lifecycle and artifact-first rules | Fail closed on trust-critical violations |
| Canon docs footprint | Fragmented | Consolidate | Prevent implementer ambiguity | One precedence order governs all conflicts |

---

## 9) Implementation Plan (Future, Not Executed)

### EXISTING
The repository can support incremental implementation; no full rewrite is required.

### PROPOSED
Execution order (design only; no implementation in this run):

1. **Canon lock alignment**
- Resolve and publish final canon precedence and lifecycle semantics.
- Success: no doc/runtime contradiction on commit vs submit.

2. **DB-first ingestion representation**
- Add additive tables/columns needed for deterministic website ingestion runs/pages/summaries.
- Success: ingestion and verification are fully representable in Supabase.

3. **Edge ingestion behavior integration**
- Extend `next-turn` to orchestrate ingest+verify posture transitions using persisted state.
- Success: artifact sessions begin with comprehension verification before narrowing.

4. **Commit/submit boundary correction**
- Align endpoint semantics to review-before-submit truth.
- Success: commit no longer implies final bundle submission side effect.

5. **iOS contract wiring updates**
- Add artifact request support and lifecycle-accurate commit/submit UX actions.
- Success: one intake surface, conversation never blocked by gates, commit blocked when required.

6. **Verification expansion and CI hardening**
- Add behavior checks and smoke paths for ingestion partial/failed scenarios.
- Success: trust/lifecycle regressions fail verification before merge.

UNKNOWN:
- Whether queue-based background ingestion orchestration is required immediately depends on observed edge runtime limits during implementation.

### Backwards Compatibility / Legacy Runs Handling (LOCKED)
Legacy runs created under earlier semantics (where commit also triggered submit) SHALL be treated as historical records, not rewritten to new semantics.
- Existing legacy rows in `contract_versions`, `submission_artifacts`, and related audit records SHALL remain immutable and SHALL NOT be reinterpreted silently.
- v3 behavior SHALL apply only to new runs/cycles after rollout; legacy records SHALL be surfaced as legacy semantics in operator/client views where needed.
- If status normalization is required for reporting, it SHALL be implemented as explicit derived labeling (or additive metadata), not destructive mutation of historical rows.
- UI/UX display of legacy runs SHALL preserve user trust by indicating legacy mode rather than pretending old runs followed v3 review-before-submit semantics.

---

## 10) Human Ops Runbook (Terminal Commands Required)

### EXISTING
Repo already contains Supabase workflows and verification scripts.

### PROPOSED
Use this sequence when implementation begins.

1) Repository and tooling baseline
```bash
cd /Users/andysalvo_1/Documents/GitHub/ShipFirst
git status -sb
supabase --version
```

2) Supabase auth/link (if not already linked)
```bash
supabase login
supabase link --project-ref <PROJECT_REF>
```

3) Apply additive migrations
```bash
supabase db push
```

4) Set required function secrets (placeholders only)
```bash
supabase secrets set OPENAI_API_KEY="<OPENAI_API_KEY>" \
  SUPABASE_SERVICE_ROLE_KEY="<SUPABASE_SERVICE_ROLE_KEY>" \
  SHIPFIRST_BRAIN_VERSION="shipfirst-brain-v3"
```

5) Deploy Phase 1 functions
```bash
supabase functions deploy next-turn --no-verify-jwt
supabase functions deploy commit-contract --no-verify-jwt
supabase functions deploy submit-run --no-verify-jwt
```
Binding warning: `--no-verify-jwt` disables gateway JWT verification only; each function SHALL still enforce JWT authentication and project ownership authorization internally before any project-scoped read/write.

6) Run behavior gate checks
```bash
bash scripts/verify_interview_engine_contract.sh
```

7) Run DB contract checks (password-safe flow)
```bash
export DATABASE_URL="postgresql://postgres.<PROJECT_REF>@aws-0-us-west-2.pooler.supabase.com:5432/postgres"
read -rs "PGPASSWORD?DB password: " PGPASSWORD; echo
export PGPASSWORD
bash scripts/verify_db_contract.sh
```

8) Build and run iOS tests
```bash
xcodebuild \
  -project ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  test
```

9) API smoke for interview path
```bash
export TEST_EMAIL="<TEST_EMAIL>"
export TEST_PASSWORD="<TEST_PASSWORD>"
bash scripts/smoke_interview_engine.sh
```

10) Optional storage artifact check (operator token required)
```bash
curl -s "https://api.supabase.com/v1/projects/<PROJECT_REF>/storage/buckets/shipfirst-submissions/objects?limit=20" \
  -H "Authorization: Bearer <SUPABASE_ACCESS_TOKEN>" \
  -H "Content-Type: application/json"
```

---

## 11) Risk & Trust Analysis

### EXISTING
Current risk profile already includes schema/contract drift and endpoint semantics drift; trust-critical enforcement exists but is unevenly expressed across docs and runtime.

### PROPOSED
New v3 ingestion risks and mitigations:

1. **SSRF / internal target access**
- Mitigate with strict URL validation, protocol allowlist, private-network denial, redirect bounds.

2. **Malicious or oversized HTML payloads**
- Mitigate with content-type allowlist, byte caps, timeout caps, and parser safety constraints.

3. **Cross-tenant leakage in retrieval/summary**
- Mitigate with project-scoped tables + RLS via `user_owns_project(project_id)` and no unauthenticated read path.

4. **Silent certainty laundering from artifact-derived text**
- Mitigate by defaulting artifact-derived claims to `ASSUMED` and requiring explicit confirmation linkage to promote.

5. **False confidence from partial ingestion**
- Mitigate with explicit `partial/failed` states and mandatory uncertainty surfacing before narrowing.

6. **Replay/debug blind spots**
- Mitigate by persisting ingest attempts, source hashes, posture transitions, and correlation metadata.

Intentionally deferred (explicit):
- JS browser rendering, authenticated crawling, broad autonomous retrieval dependencies.

UNKNOWN:
- Final threat-model depth for anti-bot/abuse controls beyond baseline rate/size/time limits.

---

## 12) Go / No-Go Checklist

### EXISTING
The repo is close but not yet contract-clean for v3 behavior.

### PROPOSED
Implementation approval requires all items true:

- [ ] Canon precedence is explicitly accepted and referenced by implementation PRs.
- [ ] Commit-vs-submit lifecycle semantics are consistent in docs and runtime behavior.
- [ ] Artifact ingestion is represented and persisted as first-class state (including partial/failed outcomes).
- [ ] Artifact-first comprehension verification is enforced before directional narrowing.
- [ ] Trust promotion rule is enforced globally (`USER_SAID` requires explicit confirmation linkage).
- [ ] UNKNOWN durability is preserved; unresolved ambiguity does not get silently rewritten.
- [ ] All customer-path trust-critical state remains in Supabase (no hidden app-only truth).
- [ ] Behavior and DB verification scripts both pass in target environment.
- [ ] iOS remains one intake surface with no Phase 1 scope expansion.
- [ ] Security limits for ingestion are implemented and audited.

**GO** only when all checklist items are true.
**NO-GO** if any checklist item fails, especially trust-boundary or lifecycle-consistency checks.
