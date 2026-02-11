# Acceptance Tests (Behavioral, Plain English)

1) Starting from a vague first sentence, the engine asks one answerable clarifying question instead of forcing a feature bundle.

2) After two vague user turns, the engine may propose possible directions, but labels them as possibilities and not facts.

3) If a website is provided, the next turn is comprehension verification, not directional feature selection.

4) If artifact ingestion is incomplete, the engine explicitly states uncertainty before proceeding.

5) A user correction to system interpretation updates state and is reflected in the next turn.

6) The engine never promotes a hypothesis to user-stated truth without an explicit confirmation event.

7) UNKNOWN items persist across turns until explicitly resolved; they are not silently removed.

8) When a prompt causes overload (PAUSE-like signal), the next prompt shrinks cognitive surface and lowers abstraction.

9) No early turn asks the user to choose architecture-like framing (for example “public tool vs internal tool”) before context is verified.

10) A checkpoint prompt always includes a `none fit` path and accepts custom correction.

11) If two high-impact claims conflict, contradiction remains explicit and blocks silent progression.

12) If the user repeatedly answers “yes,” the engine runs one nuance probe before treating consensus as deep.

13) Each turn has one cognitive job; mixed-job prompts fail acceptance.

14) Artifact-based interviews maintain lower question volume initially compared with no-artifact interviews.

15) Commit readiness can be blocked by unresolved unknowns/contradictions, but conversation flow is not blocked from continuing.

16) Engine logs are sufficient to replay why a prompt was asked: posture mode, move type, evidence refs, and trust-layer transitions are recoverable.
