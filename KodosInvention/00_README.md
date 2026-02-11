# KodosInvention Canon
Status: Binding

## Purpose
This folder freezes pre-implementation orientation for rebuilding the iOS intake surface as ShipFirst Kodos without drifting from backend truth. It defines what is normative for the rebuild and what is only descriptive evidence. It is not a feature wishlist and it does not authorize production code changes by itself.

## Binding Statements
- Kodos is a client surface over existing project-scoped backend truth, not a new product system.
- Canon precedence for these docs is governed by `CANON_PRECEDENCE.md`; runtime code is evidence of current state, not intent authority.
- The rebuild must preserve Phase 1 invariants: one intake surface, server-side inference only, strict ownership, no silent promotion, commit separated from submit, and exactly-10 at commit.
- Any statement here that cannot be traced to explicit repo evidence is non-binding and must be marked UNKNOWN.

## Definitions
- Kodos: The rebuilt iOS intake interaction surface that resolves backend state toward commit-ready truth.
- Run: One intake lifecycle identified by `(project_id, cycle_no)`.
- Canon: Binding intended-truth documents plus enforced runtime contracts and verifiers.

## Evidence Pointers
- `CANON_PRECEDENCE.md`
- `pre-spec/ShipFirst_v3_PreImplementation_Spec.md`
- `ShipFirstBrain_Canonical/01_Platform_Definition.md`
- `InterviewEngine/README.md`
- `scripts/verify_interview_engine_contract.sh`
- `scripts/verify_db_contract.sh`
