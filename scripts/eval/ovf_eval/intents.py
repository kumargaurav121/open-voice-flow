"""Scores parsed commands (ticket 11) against the expected parses in docs/eval/references.json.

The recipient must match exactly (ignoring case; the app has already respelled names with the dictionary).
Two verdicts for the message:
- **strict**: the same words as expected after normalising numbers, case and spelling variants. A wrong
  pronoun ("he can merge" for "you can merge") fails: turning reported speech into direct speech is what
  the model path is for.
- **lenient** (`ok`): within `MAX_TEXT_WER` of the expected text, for transcription noise.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from .normalize import normalize
from .score import edits, sound_keys

MAX_TEXT_WER = 0.25


@dataclass(frozen=True)
class Expected:
    id: int
    app: str
    to: str
    text: str


@dataclass(frozen=True)
class Parsed:
    id: int
    intent: dict[str, Any] | None
    seconds: float


@dataclass(frozen=True)
class IntentResult:
    id: int
    ok: bool
    strict: bool
    text_wer: float
    reason: str
    seconds: float | None


def _text_wer(reference: str, hypothesis: str) -> float:
    ref, hyp = sound_keys(normalize(reference)), sound_keys(normalize(hypothesis))
    return edits(ref, hyp) / max(len(ref), 1)


def score_intents(expected: Sequence[Expected], parsed: Sequence[Parsed]) -> list[IntentResult]:
    by_id = {p.id: p for p in parsed}
    results = []
    for e in expected:
        p = by_id.get(e.id)
        if p is None:
            results.append(IntentResult(e.id, False, False, 1.0, "no parse saved", None))
            continue
        intent = p.intent or {}
        if intent.get("action") != "send_message":
            results.append(IntentResult(e.id, False, False, 1.0, "not understood", p.seconds))
            continue
        problems = []
        if str(intent.get("app", "")).lower() != e.app:
            problems.append(f"app {intent.get('app')!r}")
        if normalize(str(intent.get("to", ""))) != normalize(e.to):
            problems.append(f"to {intent.get('to')!r}")
        wer = _text_wer(e.text, str(intent.get("text", "")))
        if wer > MAX_TEXT_WER:
            problems.append(f"text {wer:.0%} off")
        ok = not problems
        results.append(IntentResult(e.id, ok, ok and wer == 0, wer, ", ".join(problems) or "ok", p.seconds))
    return results
