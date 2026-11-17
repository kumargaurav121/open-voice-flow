"""Scores sentence breaks: whether the output ends sentences where the reference does.

Word error rate ignores punctuation, so it can't see a full stop put in the middle of a sentence (as
when a dictation is transcribed in parts, each ending with one). Each output word is lined up with the
reference (script-agnostic, so spelling variants match), and a break is a word ending in . ? or !:
- **found**: a break in both;
- **false**: a break in the output only;
- **missed**: a break in the reference only.
The last word of a text is left out: every dictation ends a sentence there.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from difflib import SequenceMatcher

from .normalize import normalize
from .score import Item, Transcript, sound_keys

ENDINGS = (".", "?", "!")


@dataclass(frozen=True)
class Breaks:
    found: int
    false: int
    missed: int

    @property
    def precision(self) -> float:
        return self.found / max(self.found + self.false, 1)

    @property
    def recall(self) -> float:
        return self.found / max(self.found + self.missed, 1)


def _words_and_breaks(text: str) -> tuple[list[str], list[bool]]:
    """Normalised words, and whether each one ends a sentence (except the text's last word)."""
    keys: list[str] = []
    ends: list[bool] = []
    for token in text.split():
        words = sound_keys(normalize(token))
        if not words:
            continue
        keys += words
        ends += [False] * (len(words) - 1) + [token.rstrip("\"')]").endswith(ENDINGS)]
    if ends:
        ends[-1] = False
    return keys, ends


def score_breaks(items: Sequence[Item], transcripts: Sequence[Transcript]) -> Breaks:
    by_id = {t.id: t for t in transcripts}
    found = false = missed = 0
    for item in items:
        if item.id not in by_id:
            continue
        ref, ref_ends = _words_and_breaks(item.reference)
        hyp, hyp_ends = _words_and_breaks(by_id[item.id].text)
        for block in SequenceMatcher(None, ref, hyp, autojunk=False).get_matching_blocks():
            for k in range(block.size):
                r, h = ref_ends[block.a + k], hyp_ends[block.b + k]
                found += r and h
                false += h and not r
                missed += r and not h
    return Breaks(found, false, missed)
