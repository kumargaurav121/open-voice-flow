"""Script-agnostic word matching.

Whisper may write a Hindi word in Devanagari ("ज़्यादा") while the reference uses a romanisation
("zyada", "jyada"). `sound_key` maps both to the same loose skeleton so the score reflects what the
model heard rather than which script it chose. Medial vowels are dropped (romanisations disagree on
them) but the final vowel is kept as a class, because Hindi grammar lives there: ka/ki/ke/ko and
hai/ho must stay different. Some distinct words still collide (hai/he, main/mein), so this metric is
reported alongside a strict one.
"""

import re

from indic_transliteration import sanscript

_DEVANAGARI = re.compile(r"[ऀ-ॿ]")

# ITRANS spellings that don't survive lowercasing, mapped to plain letters (order matters).
_ITRANS = [
    ("aॉ", "o"), ("aॅ", "e"),    # candra o / e replace the inherent vowel (laptop)
    ("ॉ", "o"), ("ॅ", "e"),      # ...and are left untransliterated by ITRANS
    ("~N", "n"), (".N", "n"), ("M", "n"),  # nasals: chandrabindu, anusvara
    (".Dh", "d"), (".D", "d"),             # flapped ड़ / ढ़
    ("Sh", "s"),
]

_FOLD = str.maketrans("zwq", "jvk")

# Final vowel group -> class. Long/short and common romanisation variants share a class.
_ENDINGS = {"a": "a", "aa": "a", "i": "i", "ee": "i", "ii": "i", "e": "e", "ai": "e", "ei": "e", "ae": "e",
            "o": "o", "oo": "o", "u": "o", "uu": "o", "au": "o", "ou": "o"}


def _romanize(word: str) -> str:
    if not _DEVANAGARI.search(word):
        return word
    text = str(sanscript.transliterate(word, sanscript.DEVANAGARI, sanscript.ITRANS))
    for itrans, plain in _ITRANS:
        text = text.replace(itrans, plain)
    # ITRANS writes the unpronounced inherent vowel of a final consonant as lowercase "a"
    # (देर -> "dera"); a real long ā is uppercase "A" (खाना -> "khAnA").
    return re.sub(r"(?<=[^aeiouAEIOU])a$", "", text)


def sound_key(word: str) -> str:
    """Loose phonetic skeleton of one word, comparable across Devanagari and romanised Hindi."""
    key = re.sub(r"[^a-z]", "", _romanize(word).lower())
    if not key:
        return word  # another script entirely: only an identical word matches
    key = key.replace("ph", "f").translate(_FOLD)
    key = re.sub(r"([bcdgjkpts])h", r"\1", key)  # drop aspiration: kh→k, bh→b, th→t, sh→s
    key = re.sub(r"(?<=[aeiou])h$", "", key)  # silent final h: toh, yeh
    ending_match = re.search(r"[aeiou]+$", key)
    ending = ending_match[0] if ending_match else ""
    body = key[: len(key) - len(ending)]
    body = body[:1] + re.sub(r"[aeiou]", "", body[1:])
    return re.sub(r"(.)\1+", r"\1", body) + _ENDINGS.get(ending, ending[:1])
