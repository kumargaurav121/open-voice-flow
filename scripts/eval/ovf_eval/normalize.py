"""Text normalisation so formatting differences don't count as recognition errors."""

import re
import unicodedata

from num2words import num2words

# Letters (any script, incl. Devanagari vowel signs and nukta), digits and apostrophes survive.
# The danda (।, ॥) is punctuation even though it sits in the Devanagari block.
_NOT_WORD = re.compile(r"[^\w'ऀ-ॣ०-ॿ]+")

_CONTRACTIONS = {
    "i'm": "i am", "i've": "i have", "i'll": "i will", "i'd": "i would",
    "we're": "we are", "we've": "we have", "we'll": "we will",
    "you're": "you are", "you've": "you have", "you'll": "you will",
    "they're": "they are", "it's": "it is", "that's": "that is", "let's": "let us",
    "can't": "can not", "don't": "do not", "won't": "will not", "isn't": "is not",
    "aren't": "are not", "didn't": "did not", "doesn't": "does not",
}

_UNITS = {"ms": "milliseconds", "am": "am", "pm": "pm"}

_THOUSANDS = re.compile(r"(?<=\d),(?=\d{3}\b)")
# "11.30" / "11:30" read as clock times; other dotted numbers are decimals.
_TIME = re.compile(r"\b([01]?\d|2[0-3])(?::|\.(?=[0-5]\d\b))([0-5]\d)\b")
_DECIMAL = re.compile(r"\b(\d+)\.(\d+)\b")
_ORDINAL = re.compile(r"\b(\d+)(st|nd|rd|th)\b")
_NUMBER_UNIT = re.compile(r"\b(\d+)(ms|am|pm)\b")
_YEAR = re.compile(r"\b(19|20)\d{2}\b")
_NUMBER = re.compile(r"\b\d+\b")


def _words(n: int, *, ordinal: bool = False) -> str:
    return str(num2words(n, to="ordinal" if ordinal else "cardinal"))


def _time(match: re.Match[str]) -> str:
    hours, minutes = int(match[1]), int(match[2])
    if minutes == 0:
        return _words(hours)
    return f"{_words(hours)} {'oh ' if minutes < 10 else ''}{_words(minutes)}"


def _decimal(match: re.Match[str]) -> str:
    return f"{_words(int(match[1]))} point {' '.join(_words(int(d)) for d in match[2])}"


def _spell_numbers(text: str) -> str:
    text = _THOUSANDS.sub("", text)
    text = _TIME.sub(_time, text)
    text = _DECIMAL.sub(_decimal, text)
    text = _YEAR.sub(lambda m: str(num2words(int(m[0]), to="year")), text)
    text = _ORDINAL.sub(lambda m: _words(int(m[1]), ordinal=True), text)
    text = _NUMBER_UNIT.sub(lambda m: f"{_words(int(m[1]))} {_UNITS[m[2]]}", text)
    return _NUMBER.sub(lambda m: _words(int(m[0])), text)


def normalize(text: str) -> list[str]:
    """Lowercase, expand contractions and numbers, strip punctuation, split into words."""
    text = unicodedata.normalize("NFC", text).lower().replace("’", "'")
    text = re.sub(r"[\w']+", lambda m: _CONTRACTIONS.get(m[0], m[0]), text)
    text = _spell_numbers(text)
    # num2words emits hyphens and commas ("twenty-one", "one hundred and five"); split them too.
    words = _NOT_WORD.sub(" ", text.replace("-", " ")).split()
    return [w.strip("'") for w in words if w.strip("'")]
