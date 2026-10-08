"""Word error rate scoring over the eval set."""

import math
import statistics
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from .normalize import normalize
from .script import sound_key

# A non-English clip whose output shares fewer than this fraction of reference words
# (script-agnostically) was almost certainly translated rather than transcribed.
TRANSLATION_OVERLAP = 0.3


@dataclass(frozen=True)
class Item:
    id: int
    lang: str
    reference: str
    reference_devanagari: str | None = None


@dataclass(frozen=True)
class Transcript:
    id: int
    text: str
    seconds: float


@dataclass(frozen=True)
class Score:
    strict_wer: float
    agnostic_wer: float
    reference_words: int


@dataclass
class _Tally:
    strict_edits: int = 0
    agnostic_edits: int = 0
    reference_words: int = 0

    def add(self, reference: list[str], hypothesis: list[str]) -> None:
        self.strict_edits += _edits(reference, hypothesis)
        self.agnostic_edits += _edits(_keys(reference), _keys(hypothesis))
        self.reference_words += len(reference)

    def score(self) -> Score:
        words = self.reference_words or 1  # nothing to get wrong: report 0, not a crash
        return Score(self.strict_edits / words, self.agnostic_edits / words, self.reference_words)


@dataclass(frozen=True)
class Report:
    overall: Score
    by_language: dict[str, Score]
    latency_median: float
    latency_p95: float
    translated: list[int]


def _edits(reference: Sequence[str], hypothesis: Sequence[str]) -> int:
    """Word-level Levenshtein distance."""
    previous = list(range(len(hypothesis) + 1))
    for i, ref in enumerate(reference, 1):
        current = [i]
        for j, hyp in enumerate(hypothesis, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ref != hyp)))
        previous = current
    return previous[-1]


def _keys(words: Iterable[str]) -> list[str]:
    return [sound_key(w) for w in words]


def _looks_translated(lang: str, reference: list[str], hypothesis: list[str]) -> bool:
    if lang == "en" or not reference:
        return False
    hyp_keys = set(_keys(hypothesis))
    shared = sum(key in hyp_keys for key in _keys(reference))
    return shared / len(reference) < TRANSLATION_OVERLAP


def _nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(percentile * len(ordered)) - 1)]


def score(items: Sequence[Item], transcripts: Sequence[Transcript], *, devanagari_references: bool = False) -> Report:
    """Corpus WER (total edits / total reference words), strict and script-agnostic, per language."""
    by_id = {t.id: t for t in transcripts}
    overall = _Tally()
    by_language: dict[str, _Tally] = defaultdict(_Tally)
    translated = []

    for item in items:
        latin = normalize(item.reference)
        devanagari = item.reference_devanagari if devanagari_references else None
        reference = normalize(devanagari) if devanagari else latin
        hypothesis = normalize(by_id[item.id].text)
        overall.add(reference, hypothesis)
        by_language[item.lang].add(reference, hypothesis)
        # Overlap is script-agnostic, so the Latin reference works whatever script the output uses.
        if _looks_translated(item.lang, latin, hypothesis):
            translated.append(item.id)

    latencies = [by_id[item.id].seconds for item in items]
    return Report(
        overall=overall.score(),
        by_language={lang: tally.score() for lang, tally in by_language.items()},
        latency_median=statistics.median(latencies),
        latency_p95=_nearest_rank(latencies, 0.95),
        translated=translated,
    )
