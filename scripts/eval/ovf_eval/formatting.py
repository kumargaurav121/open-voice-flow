"""Scores the final text of the formatting items (38-44) against their `expected_output` in
docs/eval/references.json.

Three views, because transcription errors ("yah" for "yeh", "5" for "five") would otherwise hide whether
the formatting itself worked:
- **exact**: the text equals the expected output, ignoring case and spacing within lines. Line breaks,
  paragraph breaks (any number of blank lines is one), punctuation and list numbers all count. A miss
  gets a similarity (0-1) to show how close it was.
- **words_wer**: word errors against the expected output, normalised and script-agnostic like the main
  score, so a filler or self-correction left in shows up while spelling variants don't.
- **layout_ok**: the same lines, paragraph breaks and list numbers, whatever the sentence punctuation.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from difflib import SequenceMatcher

from .score import Transcript, text_wer


@dataclass(frozen=True)
class ExpectedFormat:
    id: int
    text: str


@dataclass(frozen=True)
class FormatResult:
    id: int
    exact: bool
    similarity: float
    expected: str
    actual: str | None
    words_wer: float
    layout_ok: bool


def _normalised(text: str) -> str:
    """Lowercase, one space between words, no blank lines at the ends, at most one blank line in a row."""
    lines = [re.sub(r"[ \t]+", " ", line).strip().lower() for line in text.strip().splitlines()]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines))


def _skeleton(text: str) -> list[str]:
    """Each line as blank, a list item's number, or plain text."""
    return ["" if not line else (m.group(1) if (m := re.match(r"(\d+)[.)] ", line)) else "text")
            for line in _normalised(text).split("\n")]


def score_formatting(expected: Sequence[ExpectedFormat], transcripts: Sequence[Transcript]) -> list[FormatResult]:
    by_id = {t.id: t for t in transcripts}
    results = []
    for item in expected:
        transcript = by_id.get(item.id)
        if transcript is None:
            results.append(FormatResult(item.id, False, 0.0, item.text, None, 1.0, False))
            continue
        want, got = _normalised(item.text), _normalised(transcript.text)
        results.append(FormatResult(item.id, want == got, SequenceMatcher(None, want, got).ratio(), item.text,
                                    transcript.text, text_wer(item.text, transcript.text),
                                    _skeleton(item.text) == _skeleton(transcript.text)))
    return results
