# Interview Engine (Pre-Implementation Canonical)

## What This Is
This folder freezes the minimum internal thinking framework for an adaptive interview engine that ShipFirst can wire into the existing intake product.  
It is a behavior contract for interviewing under uncertainty, not an implementation spec.

## What This Is Not
- Not a UI spec.
- Not a data schema migration.
- Not Edge Function code.
- Not a 10-doc generation design.

## How It Wires Into ShipFirst (High-Level)
- ShipFirst client submits a turn and receives a next move from the engine boundary.
- The engine updates interview state (certainty, uncertainty, posture, burden signals) and returns the next prompt style.
- Commit-time generation remains downstream and is only allowed after readiness is earned.

## Pre-Implementation Means
Pre-implementation here means we are locking behavior laws and handshake expectations before writing new engine logic.  
If behavior is unclear in this folder, implementation should not proceed.  
If behavior is clear but repository contracts cannot represent it, audit deltas must land first.

## Reading Order
1. `ThinkingFramework.md`
2. `PostureModes.md`
3. `AllowedMoves.md`
4. `ArtifactHandling.md`
5. `Handshake.md`
6. `AcceptanceTests.md`
