# Drift Report

## Unifying Definition of ShipFirst (Phase 1 Truth)
ShipFirst Phase 1 is a customer-facing intake system that captures meaning, forces explicit alignment, and produces a governed contract packet of exactly 10 documents that users review before final submission. It is the pre-operation substrate for future owner-operated apps: it does not run customer apps yet, but it establishes the trust, ownership, and audit boundaries those future operations require. The active loop is intake, confirmation, contract generation, review, and submission bundle handoff to private storage with strong provenance and access control. The system is intentionally narrow now so later operations can scale without rewriting core truth.

## Phase 2 Promise (Non-Binding)
Phase 2 is expected to add owner-operated runtime controls and app operations surfaces, but only after Phase 1 invariants remain stable in production and verification gates are reliable. This is a direction, not a shipped commitment, and no Phase 2 capability is assumed by current contracts.

## Drift Summary Table

| Document | Drift Severity (0-3) | Summary |
|---|---:|---|
| `01_Platform_Definition.md` | 2 | Accurate contracts, but overly builder/platform phrasing and weak "owner-ops later" framing. |
| `02_Product_Surfaces.md` | 2 | Good surface separation, but Dev Central language risks centralizing control too early. |
| `03_Identity_Ownership_RLS.md` | 1 | Strong technical contract; needs clearer owner/operator language and less internal-only tone. |
| `04_ControlPlane_Data_Model.md` | 2 | Correct entities, but reads as engineering schema map, not founder-usable operational substrate. |
| `05_Edge_Functions_and_Server_Boundary.md` | 1 | Mostly aligned; needed clearer relation to user-visible trust and review flow. |
| `06_Verification_and_Drift_Prevention.md` | 2 | Correct checks but phrasing was CI/engineering heavy and under-explained for operators. |
| `07_Security_Threat_Model_BreakGlass.md` | 2 | Good controls, but mixed "expected" vs "implemented" language and premature enterprise framing. |
| `08_AI_Readiness_and_Embeddings_Policy.md` | 1 | Mostly correct; needed tighter scope guard to avoid implied near-term vector productization. |
| `09_Public_Signal_Extraction.md` | 1 | Useful claims; needed stricter linkage to what is currently implemented in Phase 1. |
| `10_Open_Questions_and_Phase_Gates.md` | 2 | Strong questions, but phase gates were too engineering-only and not owner-agency oriented. |

## Findings by Document

### `01_Platform_Definition.md`
- Describes platform truth well, but centers builder/process framing more than owner trust and eventual owner operation.
- "Frozen" language is precise but not accessible for non-engineering operators.
- Phase 1 exclusions are correct but can be read as permanent product limits instead of staged scope.
- Needs stronger statement that Phase 1 is a pre-operation substrate for future owner-operated apps.

### `02_Product_Surfaces.md`
- Correctly keeps one active customer surface in Phase 1.
- "Dev Central" description risks implying broad internal override authority.
- Surface outcomes should be tied to user trust, review, and submission lifecycle.
- Future surface text needed stronger explicit out-of-scope guardrails.

### `03_Identity_Ownership_RLS.md`
- Canonical ownership model is solid and enforceable.
- Terminology is technically correct but not cross-functional enough.
- Needed clearer distinction between owner-visible guarantees and internal implementation details.

### `04_ControlPlane_Data_Model.md`
- Correct table set and invariants.
- Drift toward schema-inventory style made intent less legible for product/ops readers.
- Needed explicit mapping from records to run lifecycle and owner review behavior.
- Needed stronger statement that this model preserves meaning, not app implementation mechanics.

### `05_Edge_Functions_and_Server_Boundary.md`
- Security boundary is correctly defined.
- Required clearer explanation of how server gates protect no-silent-inference and exactly-10 guarantees.
- Error model needed clearer operator interpretation guidance.

### `06_Verification_and_Drift_Prevention.md`
- Checks were useful but framed mostly as engineering gate plumbing.
- Needed explicit connection to Phase 1 customer promise and safe operation.
- Needed clearer differentiation between implemented gates and intended future automation.

### `07_Security_Threat_Model_BreakGlass.md`
- Threats and controls are relevant.
- Break-glass governance was under-specified as an operational workflow for a small team.
- Needed tighter wording around what is currently enforced vs expected discipline.

### `08_AI_Readiness_and_Embeddings_Policy.md`
- Correctly keeps embeddings out of Phase 1 critical path.
- Needed stronger anti-drift language to prevent speculative AI scope in active roadmap.
- Needed clearer tie-back to trust labels/provenance invariants.

### `09_Public_Signal_Extraction.md`
- Claims were mostly factual and reusable.
- Needed explicit "only claim what is implemented" rule.
- Needed wording to prevent forward-looking claims from being mistaken as shipped scope.

### `10_Open_Questions_and_Phase_Gates.md`
- Open questions are strong and relevant.
- Phase gates leaned toward internal mechanics rather than user-visible readiness.
- Needed stronger anti-drift triggers tied to Phase 1 invariant failures.

