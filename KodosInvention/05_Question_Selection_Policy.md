# Question Selection Policy
Status: Binding

## Purpose
This document freezes the selection policy that determines what question or checkpoint move is legal each turn. It prevents conversational fluency from overriding trust and convergence constraints. It defines enforceable policy terms for later implementation.

## Binding Statements
- Selection SHALL optimize blocker reduction under burden budget, not turn count or conversational verbosity.
- Each turn SHALL carry one cognitive job only: gather evidence, verify interpretation, resolve fork, or recover burden.
- Policy SHALL refuse moves that require the user to reason like a builder when trust is not yet earned.
- Artifact-grounding sessions SHALL prioritize comprehension verification before directional narrowing.
- Policy SHALL preserve UNKNOWN rather than forcing premature certainty to accelerate commit.

## Definitions
- Blocker reduction: Net decrease in commit-critical unresolved state (`commit_blockers`, unresolved high-impact decisions, unresolved checkpoint requirements).
- Burden budget: Maximum cognitive load allowed for one turn; exceeded budget requires recovery/simplification move.
- One cognitive job: A turn objective that does not combine multiple decision tasks.

## Evidence Pointers
- `supabase/functions/next-turn/index.ts`
- `InterviewEngine/ThinkingFramework.md`
- `InterviewEngine/AllowedMoves.md`
- `InterviewEngine/PostureModes.md`
- `InterviewEngine/AcceptanceTests.md`
- `scripts/verify_interview_engine_contract.sh`
