# Thinking Framework

## Core Principle
Control epistemic pace before optimizing conversational volume.  
A fluent conversation that advances without justified certainty is a trust failure.

## Four Control Variables

### 1) Certainty State
Tracks what the system currently treats as known enough to build on.  
Must be layered, not binary.

### 2) Burden State
Tracks user cognitive strain per turn.  
A turn is invalid if it demands product-planning reasoning from a user still expressing raw intent.

### 3) Pace State
Tracks how quickly the interview is narrowing.  
Narrowing should be event-driven by high-impact ambiguity, not cadence-driven.

### 4) Trust State
Tracks whether the system has earned the right to ask directional questions.  
Trust rises when understanding is verified; trust falls when the system pushes decisions before comprehension proof.

## Trust Boundary
The engine must preserve three epistemic layers:
- `USER_SAID`: directly attributable to user input.
- `HYPOTHESIZED`: inferred candidate meaning pending explicit confirmation.
- `UNKNOWN`: unresolved but material.

Repository note:
- Current repo uses `ASSUMED` in several contracts. For implementation safety, treat `ASSUMED` as the legacy label for `HYPOTHESIZED` until a naming migration is explicitly approved.

## Non-Negotiable Internal Rules
- Unknown is valid state, not error state.
- Hypotheses must never auto-promote to user truth.
- Contradictions are surfaced before new narrowing.
- One turn must carry one cognitive job.
- Burden spikes are calibration events, not user failures.

## Primary Tradeoffs
- TRADE-OFF: Early verification builds trust but can feel slower.
- TRADE-OFF: Fast narrowing increases momentum but raises silent-assumption risk.
- TRADE-OFF: Constrained prompts reduce burden but can over-anchor if introduced before context is verified.
- TRADE-OFF: Open prompts preserve creativity but can become non-answerable if the user lacks frame.

## Failure Modes To Guard Against
- Clarity theater: polished outputs without stable meaning.
- Shallow consensus: repeated “yes” interpreted as depth.
- Premature narrowing: forced forks before understanding.
- Builder-lane drift: asking users to reason like implementation planners.
- Silent certainty laundering: inferred claims presented as user truth.
