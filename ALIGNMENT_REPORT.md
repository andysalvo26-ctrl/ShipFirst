# ShipFirst Repository Alignment Report

Generated: 2026-02-10
Mode: Audit-only (no implementation changes)

## Executive Summary
This repository is **partially aligned** to the intended Phase 1 intake direction. The core intake runtime exists and compiles, server boundaries are active, strict ownership/RLS patterns are implemented, and commit-time exactness constraints are enforced. However, the repo currently has **canon drift** (multiple folders claiming frozen truth), **boundary drift** (docs naming older active endpoints), and **flow drift** (runtime behavior does not fully match the documented “review before final submit” contract). Implementation can proceed safely only after a small set of contract-level alignment decisions are frozen and reflected consistently in docs + scripts + endpoint contracts.

## Audit Scope and Method
This report was built by inspecting repository artifacts in this order:
1. Repo inventory (top-level directories, specs, app code, Supabase code, migrations, scripts, tests)
2. Canon determination (which artifacts claim “canonical/frozen” authority)
3. Runtime map (iOS, Edge Functions, DB schema/RLS, verification)
4. Behavior-vs-representation check (trust boundary, posture state, artifact grounding, UNKNOWN durability)
5. Drift/risk assessment and stop/go gate

No code or migration changes were applied in this run except creating this report.

## Evidence Index
Primary evidence used for critical claims:
- Product/runtime docs:
  - `README.md`
  - `VERIFY.md`
  - `ShipFirstPlatform/00_README.md`
  - `ShipFirstBrain_Canonical/01_Platform_Definition.md`
  - `ShipFirstBrain_Canonical/02_Product_Surfaces.md`
  - `ShipFirstBrain_Canonical/03_Identity_Ownership_RLS.md`
  - `ShipFirstBrain_Canonical/04_ControlPlane_Data_Model.md`
  - `ShipFirstBrain_Canonical/05_Edge_Functions_and_Server_Boundary.md`
  - `ShipFirstBrain_Canonical/06_Verification_and_Drift_Prevention.md`
- Interview engine contracts:
  - `InterviewEngine/README.md`
  - `InterviewEngine/ThinkingFramework.md`
  - `InterviewEngine/PostureModes.md`
  - `InterviewEngine/AllowedMoves.md`
  - `InterviewEngine/ArtifactHandling.md`
  - `InterviewEngine/Handshake.md`
  - `InterviewEngine/AcceptanceTests.md`
- Runtime app code:
  - `ShipFirstIntakeApp/ShipFirstIntakeApp/ShipFirstIntakeApp.swift`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp/Models.swift`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp/Info.plist`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj/project.pbxproj`
  - `ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj/xcshareddata/xcschemes/ShipFirstIntake.xcscheme`
- Edge/server code:
  - `supabase/functions/next-turn/index.ts`
  - `supabase/functions/commit-contract/index.ts`
  - `supabase/functions/generate-docs/index.ts`
  - `supabase/functions/submit-run/index.ts`
  - `supabase/functions/_shared/interview_gates.ts`
  - `supabase/functions/_shared/roles.ts`
  - `supabase/functions/_shared/brain_contract.ts`
- DB schema and hardening:
  - `supabase/migrations/20260210133000_canonical_brain_schema.sql`
  - `supabase/migrations/20260210213000_phase1_launch_hardening.sql`
  - `supabase/migrations/20260211003000_phase1_chat_loop_state.sql`
  - `supabase/migrations/20260211020000_interview_engine_state_support.sql`
  - `supabase/migrations/20260210132900_preflight_drift_backfill.sql`
  - `supabase/migrations/20260210224500_intake_turns_actor_default_safety.sql`
  - `supabase/migrations/20260210235500_decision_items_key_default_safety.sql`
- Verification and CI:
  - `scripts/verify_interview_engine_contract.sh`
  - `scripts/verify_db_contract.sh`
  - `scripts/smoke_interview_engine.sh`
  - `.github/workflows/verify-db-contract.yml`
- Canon/legacy planning context:
  - `ShipFirstBrain/README.md`
  - `ShipFirstBrain/AUDIT.md`
  - `ShipFirstBrain_Legacy/*`
  - `DataInfra/*`
  - `InterviewEngine_Audit/*`

---

## Phase 1 Scope Snapshot (as evidenced in this repo)
**Phase 1 currently implemented in code is**: one iOS intake app with auth, runs list, turn-by-turn chat intake, alignment options, commit endpoint call, and post-commit document review. (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`)

**Server boundary currently implemented**: `next-turn` for conversational loop and `commit-contract` for strict commit + exactly-10 packet + submission artifact creation; `generate-docs` and `submit-run` still exist as additional endpoints. (Evidence: `supabase/functions/next-turn/index.ts`, `supabase/functions/commit-contract/index.ts`, `supabase/functions/generate-docs/index.ts`, `supabase/functions/submit-run/index.ts`)

**Data boundary currently implemented**: project/cycle model with ownership rooted in `projects.owner_user_id`, RLS enforcement using `public.user_owns_project(project_id)`, trust labels + provenance records, submission artifact storage path recording. (Evidence: `supabase/migrations/20260210213000_phase1_launch_hardening.sql`, `supabase/migrations/20260210133000_canonical_brain_schema.sql`)

**Important operational caveat**: the canonical docs say users review all 10 docs before final submission, but current `commit-contract` creates submission artifacts during commit; iOS calls `commit-contract` directly from intake. (Evidence: `ShipFirstBrain_Canonical/01_Platform_Definition.md`, `supabase/functions/commit-contract/index.ts`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`)

---

## Canon Map
### 1) Runtime-enforced canon (highest authority)
These are executable and therefore strongest truth in this repo:
- DB schema + constraints + RLS + triggers from migrations. (Evidence: `supabase/migrations/*.sql`)
- Edge function request/response and write behavior. (Evidence: `supabase/functions/*/index.ts`)
- iOS request wiring and visible user flow. (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/*.swift`)
- Verification scripts that fail builds/checks. (Evidence: `scripts/verify_interview_engine_contract.sh`, `scripts/verify_db_contract.sh`)

### 2) Documented canon (strong intent, but can drift)
- `ShipFirstBrain_Canonical/*.md` are explicitly titled “Phase 1 Canonical” and describe current intended truth. (Evidence: `ShipFirstBrain_Canonical/01_Platform_Definition.md`)
- `InterviewEngine/*.md` declares a pre-implementation canonical behavior framework for interviewer logic. (Evidence: `InterviewEngine/README.md`)

### 3) Conflicting canon claims (drift)
- `ShipFirstPlatform/00_README.md` says this folder is frozen platform contract, but only `00_README.md` exists there; referenced `01..` docs are absent. (Evidence: `ShipFirstPlatform/00_README.md`, `ShipFirstPlatform/` directory listing)
- `ShipFirstBrain/README.md` says `ShipFirstBrain/` is frozen authoritative truth, while a separate `ShipFirstBrain_Canonical/` also claims canonical Phase 1 truth. (Evidence: `ShipFirstBrain/README.md`, `ShipFirstBrain_Canonical/01_Platform_Definition.md`)

### 4) Legacy/planning artifacts (not runtime canon)
- `ShipFirstBrain_Legacy/*` are archived legacy content. (Evidence: `ShipFirstBrain_Legacy/`)
- `DataInfra/*` and `InterviewEngine_Audit/*` are planning/audit guidance and include some now-stale findings. (Evidence: `DataInfra/README.md`, `InterviewEngine_Audit/RepoAlignmentReport.md`)

**Canon conclusion**: executable code/migrations/scripts are coherent enough to run; document canon is fragmented and must be consolidated before high-risk implementation work.

---

## System Map (As-Is Runtime)
### iOS app
- Targets/schemes:
  - App target: `ShipFirstIntake`
  - Test target: `ShipFirstIntakeTests`
  - Shared scheme: `ShipFirstIntake` (Debug test + launch configured). (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp.xcodeproj/xcshareddata/xcschemes/ShipFirstIntake.xcscheme`)
- Main screens:
  - `RootView` (config/auth/session routing)
  - `AuthView`
  - `RunsView`
  - `RunDetailView` (intake/review segments)
  - `DocumentDetailView`. (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`)
- Runtime config:
  - Reads `SHIPFIRST_SUPABASE_URL` and `SHIPFIRST_SUPABASE_ANON_KEY` from `Info.plist` build-setting substitution. (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Info.plist`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`, `Config/Supabase.xcconfig`, `project.pbxproj` base config)
- Active network loop:
  - Intake sends every turn to `next-turn`.
  - Commit action calls `commit-contract`.
  - App renders options, unresolved, commit blockers, and docs. (Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`, `ShipFirstIntakeApp/ShipFirstIntakeApp/Services.swift`)

### Edge Functions
- Discovered routes:
  - `/functions/v1/next-turn`
  - `/functions/v1/commit-contract`
  - `/functions/v1/generate-docs`
  - `/functions/v1/submit-run`.
  (Evidence: `supabase/functions/*/index.ts`)
- Shared gate helper:
  - `hasExplicitlyConfirmedBusinessType` uses explicit confirmation linkage (`decision_key`, `status=USER_SAID`, `lock_state=locked`, `confirmed_by_turn_id`). (Evidence: `supabase/functions/_shared/interview_gates.ts`)
- Trust-label aliasing:
  - `HYPOTHESIZED` maps to legacy `ASSUMED` via `normalizeTrustLabel`. (Evidence: `supabase/functions/_shared/roles.ts`)

### Database + RLS
- Core tables present in canonical schema migration:
  - `projects`, `intake_turns`, `decision_items`, `generation_runs`, `contract_versions`, `contract_docs`, `requirements`, `provenance_links`, `audit_events`, `submission_artifacts`. (Evidence: `supabase/migrations/20260210133000_canonical_brain_schema.sql`)
- Interview engine representation tables added:
  - `artifact_inputs`, `interview_turn_state`; `decision_items.confirmed_by_turn_id`, `decision_items.hypothesis_rationale`. (Evidence: `supabase/migrations/20260211020000_interview_engine_state_support.sql`)
- Ownership and RLS hardening:
  - `public.user_owns_project(project_id)`; strict project-scoped policies recreated. (Evidence: `supabase/migrations/20260210213000_phase1_launch_hardening.sql`)
- Append-only/immutability controls:
  - `intake_turns` protected from update/delete via trigger.
  - `contract_versions` protected from update/delete via trigger. (Evidence: `supabase/migrations/20260210133000_canonical_brain_schema.sql`, reinforced in `20260210213000_phase1_launch_hardening.sql`)

### Submission/artifact flow
- `commit-contract` currently performs commit and submission artifact creation in one endpoint; uploads zip to `shipfirst-submissions` and records `submission_artifacts`. (Evidence: `supabase/functions/commit-contract/index.ts`)
- `submit-run` also performs bundling/upload path for latest committed version. (Evidence: `supabase/functions/submit-run/index.ts`)

### Verification and CI
- Static behavior gate script exists and currently passes locally. (Evidence: `scripts/verify_interview_engine_contract.sh`)
- DB contract script exists and runs static gate + SQL assertions; requires `DATABASE_URL` env. (Evidence: `scripts/verify_db_contract.sh`)
- CI workflow runs DB verifier when `DATABASE_URL` secret is configured. (Evidence: `.github/workflows/verify-db-contract.yml`)

---

## Wired vs Planned (Reality Check)
### Wired now
- Chat-first intake loop (`next-turn`) with options and unresolved output shape. (Evidence: `next-turn/index.ts`, `Views.swift`)
- Commit boundary with strict packet validation and exactly-10 enforcement. (Evidence: `commit-contract/index.ts`, `_shared/brain_contract.ts`)
- Auth + ownership checks in functions using user JWT + service-role server client. (Evidence: all function `index.ts` files)
- RLS/ownership policies and project-scoped data model. (Evidence: hardening migration)
- Local simulator build and XCTest pass. (Evidence: `xcodebuild test` output)

### Planned or partially wired
- Artifact-grounding as first-class interviewer behavior is representable server-side, but client currently has no payload path for `artifact_ref` / `artifact_type`. (Evidence: `next-turn/index.ts` accepts artifact fields; `NextTurnRequest` lacks them in `Models.swift`)
- Burden/pace/posture are returned and logged server-side, but iOS shows only debug labels and does not use them for interaction policy. (Evidence: `next-turn/index.ts`, `Views.swift`)
- Legacy endpoints `generate-docs`/`submit-run` remain implemented but are not the primary app path. (Evidence: `Services.swift` usage; unused methods)

---

## What Currently Works vs Fails vs Unknown
### Verified working in this environment
- `scripts/verify_interview_engine_contract.sh` passes. (Command run during audit)
- iOS app builds and tests pass on simulator destination used in repo flow. (Command run: `xcodebuild ... test`)
- Config bridging from build settings to `Info.plist` is wired (`SHIPFIRST_SUPABASE_URL`, `SHIPFIRST_SUPABASE_ANON_KEY`). (Evidence: `Info.plist`, `Services.swift`, `project.pbxproj`)

### Verified failing or blocked in this environment
- `scripts/verify_db_contract.sh` fails without `DATABASE_URL` set (expected behavior). (Command run during audit)

### UNKNOWN (insufficient evidence in this run)
- Current remote Supabase runtime parity (schema, policies, deployed function revisions) cannot be proven without live `DATABASE_URL` + deployment checks.
- End-to-end remote flow success for `next-turn` -> `commit-contract` -> storage in this exact environment is unverified in this run.

---

## Behavior vs Representation (Trust-Critical)
### USER_SAID / ASSUMED(HYPOTHESIZED) / UNKNOWN representation
- Representable in DB and edge code today. (Evidence: `trust_label` enum in schema; `roles.ts` alias handling)
- Silent promotion protection is partially enforced by shared gate helper and verify script patterns. (Evidence: `_shared/interview_gates.ts`, `verify_interview_engine_contract.sh`)

### Posture/move/burden/pace representation
- Representable in DB (`interview_turn_state`) and emitted by `next-turn` response. (Evidence: `20260211020000_interview_engine_state_support.sql`, `next-turn/index.ts`)
- Client currently treats this mostly as debug metadata, not control policy. (Evidence: `Views.swift`)

### Artifact grounding representation
- Server supports artifact ingestion/verification states and mode shift. (Evidence: `artifact_inputs` table and `next-turn` artifact logic)
- Client does not currently send artifact refs, so this behavior is not reachable through iOS happy path. (Evidence: `NextTurnRequest` in `Models.swift`)

### Contradictions and UNKNOWN durability
- Contradiction markers exist (`has_conflict`, `conflict_key`) and commit blocks unresolved conflicts. (Evidence: `decision_items` schema, `commit-contract` gates)
- UNKNOWN is preserved in docs by packet validation checks and deterministic fallback generation. (Evidence: `_shared/brain_contract.ts`, `commit-contract/index.ts`, `generate-docs/index.ts`)

### Exactly-10 at commit boundary
- Strictly enforced in shared packet validation and commit flow. (Evidence: `_shared/brain_contract.ts`, `commit-contract/index.ts`)

---

## Drift + Risk Register
Severity legend: S0 (critical trust break), S1 (high), S2 (medium), S3 (low)

1) **S0 – Canon conflict: multiple folders claim frozen truth**
- Why it matters: implementation teams can follow different “authoritative” docs and diverge.
- Evidence: `ShipFirstBrain/README.md`, `ShipFirstBrain_Canonical/01_Platform_Definition.md`, `ShipFirstPlatform/00_README.md`.

2) **S0 – Review-before-submit contract drift**
- Why it matters: documented trust flow says user reviews 10 docs before final submission; runtime currently submits during commit.
- Evidence: `ShipFirstBrain_Canonical/01_Platform_Definition.md` vs `supabase/functions/commit-contract/index.ts` and `RunDetailView.commitContract()`.

3) **S1 – Active endpoint drift in docs**
- Why it matters: canonical docs/README still frame `generate-docs` + `submit-run` as primary while UI path is `next-turn` + `commit-contract`.
- Evidence: `README.md`, `ShipFirstBrain_Canonical/05_Edge_Functions_and_Server_Boundary.md`, `Services.swift`, `Views.swift`.

4) **S1 – Incomplete platform canonical folder**
- Why it matters: `ShipFirstPlatform/00_README.md` references contract docs that do not exist in that folder.
- Evidence: `ShipFirstPlatform/00_README.md` and `ShipFirstPlatform/` contents.

5) **S1 – Artifact-first behavior not reachable from client**
- Why it matters: server has artifact-grounding contract, but iOS request model cannot provide artifact inputs.
- Evidence: `next-turn/index.ts` expects `artifact_ref`; `Models.swift` `NextTurnRequest` lacks artifact fields.

6) **S1 – Local readiness/conflict display drift risk**
- Why it matters: `listDecisionItems` query omits `confirmed_by_turn_id`, `has_conflict`, `conflict_key`, causing client-side readiness/conflict calculations to be potentially stale/inaccurate.
- Evidence: `Services.swift` `listDecisionItems` select clause; `CommitReadinessEvaluator` in `Models.swift`; conflict UI in `Views.swift`.

7) **S2 – Parallel endpoint semantics may diverge**
- Why it matters: `commit-contract` and `submit-run` both create submission artifacts; lifecycle ownership can split and create operator confusion.
- Evidence: `commit-contract/index.ts`, `submit-run/index.ts`.

8) **S2 – Verification scripts are partly static pattern checks**
- Why it matters: grep-based checks can pass while behavior still drifts semantically.
- Evidence: `scripts/verify_interview_engine_contract.sh`.

9) **S2 – Legacy compatibility code still in hot path**
- Why it matters: actor legacy fallback and legacy `decision_items.key` safety indicate environment drift management still present in runtime paths.
- Evidence: `Services.swift` intake fallback logic, migrations `20260210224500_*`, `20260210235500_*`.

10) **S3 – Stale audit docs can mislead implementation**
- Why it matters: `InterviewEngine_Audit/*` still describe resolved issues as open.
- Evidence: `InterviewEngine_Audit/RepoAlignmentReport.md`, current `next-turn/index.ts` and migrations.

11) **S3 – Link-state path assumption mismatch**
- Why it matters: some workflows historically assumed `.supabase/project-ref`; this repo now uses `supabase/.temp/project-ref` and/or config-derived refs.
- Evidence: `supabase/.temp/project-ref`, `.supabase/` empty, scripts deriving from `Config/Supabase.xcconfig`.

12) **S1 – Secret handling risk in local environment**
- Why it matters: local function env file can contain live secrets; accidental commit risk remains if ignore rules regress.
- Evidence: `.gitignore` includes `supabase/functions/.env`; file exists locally and is untracked.

---

## Stop/Go Gate for Safe Interview Engine Implementation
### STOP triggers (unsafe to proceed)
1. Canon conflict unresolved (multiple “frozen truth” sources without explicit precedence).
2. Runtime/doc mismatch unresolved on commit lifecycle (review-before-submit vs commit-and-submit behavior).
3. Client/server handshake mismatch unresolved for artifact ingestion (`artifact_ref` contract not reachable from iOS).
4. Decision-state read-model mismatch unresolved (client computes readiness/conflicts from incomplete decision row projection).
5. Verification gate does not include at least one behavior-level runtime check beyond static grep for trust-boundary regressions.

### GO minimum conditions (safe to proceed)
1. One explicit canon precedence statement exists in-repo (which folder wins on conflict).
2. One authoritative Phase 1 runtime flow statement matches code exactly (endpoint names + when submission is created).
3. iOS-to-next-turn handshake includes artifact reference fields or docs explicitly defer artifact-grounding to later runtime.
4. Client decision fetch includes fields required for displayed readiness/conflict state, or UI explicitly treats server `can_commit`/blockers as source of truth.
5. `verify_interview_engine_contract.sh` and `verify_db_contract.sh` both pass in target environment, and at least one end-to-end smoke command path is documented and run.

Current verdict: **STOP** (close to GO after contract-alignment fixes, not architecture changes).

---

## What Must Change vs Must NOT Change
### Must change (alignment-only)
- Consolidate canonical precedence across `ShipFirstBrain_Canonical`, `ShipFirstBrain`, and `ShipFirstPlatform` docs.
- Align docs with actual active endpoint path (`next-turn` + `commit-contract`) or realign code to documented path.
- Resolve review-vs-submit lifecycle mismatch explicitly.
- Align iOS request/response/use-model with server artifact and decision-state contracts.

### Must NOT change (Phase 1 guardrails)
- Do not add new product surfaces.
- Do not weaken RLS/ownership.
- Do not move provider secrets to client.
- Do not weaken no-silent-promotion trust boundary.
- Do not move exactly-10 enforcement out of strict server commit boundary.

---

## Appendix A — Edge Function Endpoints Discovered
- `next-turn` — conversational interviewer turn processing, lightweight meaning updates, posture/move output, commit readiness hint. (`supabase/functions/next-turn/index.ts`)
- `commit-contract` — strict gate, packet generation/validation, contract persistence, submission artifact creation. (`supabase/functions/commit-contract/index.ts`)
- `generate-docs` — generation pipeline endpoint with stage gates and contract version creation/reuse. (`supabase/functions/generate-docs/index.ts`)
- `submit-run` — submission bundling endpoint for latest committed version. (`supabase/functions/submit-run/index.ts`)

## Appendix B — Key Tables Discovered (Phase 1 + interview support)
- `projects` — owner root + active cycle.
- `intake_turns` — append-only intake log.
- `decision_items` — decision state, trust label, lock state, conflict flags, confirmation linkage.
- `artifact_inputs` — artifact refs + ingestion/verification state.
- `interview_turn_state` — per-turn posture/move/burden/pace snapshot.
- `generation_runs` — stage execution trace.
- `contract_versions` — immutable contract snapshots.
- `contract_docs` — role docs (1..10).
- `requirements` — claim-level records with trust labels.
- `provenance_links` — claim evidence pointers.
- `submission_artifacts` — bundle locator + manifest metadata.
- `audit_events` — audit trail.
(Evidence: `20260210133000_canonical_brain_schema.sql`, `20260211020000_interview_engine_state_support.sql`)

## Appendix C — Key iOS Views Discovered
- `RootView` — config/session routing.
- `AuthView` — auth entry.
- `RunsView` — run list/new run.
- `RunDetailView` — intake+review flow, next-turn and commit actions.
- `DocumentDetailView` — read-only document + claims view.
(Evidence: `ShipFirstIntakeApp/ShipFirstIntakeApp/Views.swift`)

## Appendix D — Key Scripts/Tests Discovered
- `scripts/verify_interview_engine_contract.sh` — static behavior contract checks for interview function code/migration presence.
- `scripts/verify_db_contract.sh` — SQL/RLS/policy/schema contract checks (requires `DATABASE_URL`, supports `PGPASSWORD` flow).
- `scripts/smoke_interview_engine.sh` — token/project/turn/commit smoke sequence.
- XCTest:
  - `RunValidationTests.swift`
  - `SubmissionManifestTests.swift`
- CI workflow:
  - `.github/workflows/verify-db-contract.yml`

---

## Final Audit Position
The repository has a strong executable base for Phase 1 intake and trust boundaries, but **implementation safety is currently constrained more by canon/contract drift than by missing primitives**. The next safe step is alignment hardening of contracts and flow semantics (not architecture expansion).
