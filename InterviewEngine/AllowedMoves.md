# Allowed Moves

The engine should use a small move vocabulary so behavior is inspectable and replayable.

## One Cognitive Job Per Turn
Every turn must do exactly one of:
- gather signal,
- verify interpretation,
- resolve a fork,
- recover burden.

If a draft prompt spans multiple jobs, it must be rewritten or split.

## Move Vocabulary

### MOVE_OPEN_DISCOVER
- Inputs: latest user turn, unresolved high-level intent.
- Outputs: one open question.
- Preconditions: user can answer from lived context without planning jargon.
- Typical use: early exploration.

### MOVE_REFLECT_VERIFY
- Inputs: interpreted claim from user text or artifact.
- Outputs: short verification prompt (`right / mostly / wrong` style).
- Preconditions: interpreted claim materially affects direction.
- Typical use: trust-building and correction.

### MOVE_TARGETED_CLARIFY
- Inputs: one unresolved high-impact unknown.
- Outputs: one narrow open-ended question.
- Preconditions: question passes answerability test.
- Typical use: extraction after basic grounding.

### MOVE_ALIGNMENT_CHECKPOINT
- Inputs: one high-impact fork.
- Outputs: constrained options plus `none fit` plus custom path.
- Preconditions: continuing otherwise requires silent assumption.
- Typical use: lock meaning where ambiguity is expensive.

### MOVE_SCOPE_REFRAME
- Inputs: weak signal or user ambiguity.
- Outputs: example-based restatement framed as possibilities, not facts.
- Preconditions: user showed uncertainty; current prompt was non-answerable.
- Typical use: weak-signal rescue.

### MOVE_NUANCE_PROBE
- Inputs: repeated shallow confirmation (`yes` loop).
- Outputs: one light probe for missing nuance.
- Preconditions: at least two low-information confirmations in a row.
- Typical use: avoid shallow consensus.

### MOVE_PRESERVE_UNKNOWN
- Inputs: unresolved but material claim.
- Outputs: explicit unknown retention note.
- Preconditions: user has not confirmed.
- Typical use: trust boundary enforcement.

### MOVE_RECOVERY_RESET
- Inputs: burden spike indicators.
- Outputs: simplified prompt with reduced abstraction and reduced choice width.
- Preconditions: burden state above threshold.
- Typical use: PAUSE-like recovery.

## Answerability Gate (Precondition for Any Move)
Before issuing a move, internal check must pass:
- Can the user answer this from current knowledge?
- Does the prompt avoid requiring app-builder reasoning?
- Is the response burden proportional to confidence gain?

If any check fails, the move is invalid for this turn.
