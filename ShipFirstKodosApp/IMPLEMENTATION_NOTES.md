# ShipFirst Kodos — Implementation Notes

## What was reused
- Supabase auth/session handling, token refresh, and layer-aware error parsing from `ShipFirstKodosApp/ShipFirstIntakeApp/Services.swift`.
- Canonical data models (`RunSummary`, `DecisionItem`, `NextTurnResult`, `CommitContractResult`, `SubmissionResult`) from `ShipFirstKodosApp/ShipFirstIntakeApp/Models.swift`.
- Existing backend endpoints and contracts:
  - `next-turn`
  - `commit-contract`
  - `submit-run`
- Existing verifier scripts and DB contract checks in `scripts/verify_interview_engine_contract.sh` and `scripts/verify_db_contract.sh`.

## What was rebuilt
- The iOS surface flow in `ShipFirstKodosApp/ShipFirstIntakeApp/Views.swift`:
  - Welcome/Auth
  - Project home
  - Project runs
  - Turn loop
  - Commit review
  - Docs review + explicit submit
- Added client-side typed action layer in `ShipFirstKodosApp/ShipFirstIntakeApp/Models.swift` and `ShipFirstKodosApp/ShipFirstIntakeApp/Services.swift`.

## UX model (state-driven)
- The app now resolves a single product state at run home:
  - `startIntake`
  - `continueIntake`
  - `readyToCommit`
  - `reviewDocuments`
  - `submissionComplete`
- Home always shows one primary CTA based on state (`Start Intake`, `Continue Intake`, `Review Commit`, `Review Documents`, `View Submission`).
- Turn loop renders one cognitive job at a time via turn-task resolver:
  - Website context (optional first step)
  - Verification checkpoint
  - Option selection
  - Evidence input
  - Commit review handoff
- Internal fields (`posture_mode`, `move_type`, trace) are hidden from main UI and shown only in DEBUG panel.
- Production copy uses plain setup language (`Idea`, `Website Context`, `Open Questions`, `Draft Packet`, `Submitted Packet`) and avoids engine jargon.

## Routing rules
- Launch routing is deterministic: unauthenticated users see auth; authenticated users land in project home.
- Entering a run resolves state from backend truth (`turns`, `decisions`, `docs`, submission status).
- `next-turn` responses update task routing (`checkpoint`/`options`/`can_commit`) with no dead-end empty screen.
- `Commit 10 Docs` and `Submit` remain separate explicit steps; commit never submits.
- Blank Canvas starts a new cycle and clears local turn-loop draft state without deleting historical rows.

## Canon constraints enforced in client flow
- `next-turn` is the primary interaction boundary.
- Commit and submit remain separate operations.
- Commit blockers are surfaced and do not block conversation turns.
- Blank canvas is non-destructive and starts a new cycle (`projects.active_cycle_no` increment path).
- No provider secrets are embedded in app code; app uses only Supabase URL + anon key from Info.plist build settings.

## Local run commands

```bash
# behavior + db contract gates
bash scripts/verify_interview_engine_contract.sh
DATABASE_URL="postgresql://postgres.<ref>@aws-0-us-west-2.pooler.supabase.com:5432/postgres" PGPASSWORD="<db-password>" bash scripts/verify_db_contract.sh

# build + test the new Kodos project
xcodebuild \
  -project ShipFirstKodosApp/ShipFirstIntakeApp.xcodeproj \
  -scheme ShipFirstIntake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test
```

## Notes
- The original app folder `ShipFirstIntakeApp/` was left intact for reference.
- This rebuild intentionally does not alter backend production code or schema.
