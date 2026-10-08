import pytest

from ovf_eval.script import sound_key


@pytest.mark.parametrize(
    ("devanagari", "latin"),
    [
        ("ज़्यादा", "zyada"),
        ("हैं", "hain"),
        ("देर", "der"),
        ("करना", "karna"),
        ("खाना", "khaana"),
        ("थोड़ा", "thoda"),
        ("मैं", "main"),
        ("मीटिंग", "meeting"),
        ("लैपटॉप", "laptop"),
        ("गुर्जीत", "gurjeet"),
    ],
)
def test_devanagari_matches_common_romanisations(devanagari: str, latin: str) -> None:
    assert sound_key(devanagari) == sound_key(latin)


@pytest.mark.parametrize(("latin", "variant"), [("zyada", "jyada"), ("aaunga", "aunga"), ("hafte", "haphte")])
def test_romanisation_variants_match_each_other(latin: str, variant: str) -> None:
    assert sound_key(latin) == sound_key(variant)


@pytest.mark.parametrize(
    ("a", "b"),
    [
        ("kal", "aaj"), ("bhai", "build"), ("meeting", "message"), ("abhi", "bhi"),
        # Endings carry Hindi grammar; a wrong ending is a real error.
        ("ka", "ki"), ("ka", "ke"), ("ki", "ko"), ("hai", "ho"), ("kya", "ka"),
    ],
)
def test_different_words_stay_different(a: str, b: str) -> None:
    assert sound_key(a) != sound_key(b)


def test_trailing_h_after_a_vowel_is_silent() -> None:
    assert sound_key("toh") == sound_key("to")
    assert sound_key("yeh") == sound_key("ye")


def test_words_in_other_scripts_keep_their_identity() -> None:
    assert sound_key("报") != sound_key("выпуск")
    assert sound_key("报") == sound_key("报")
