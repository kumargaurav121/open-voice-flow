from ovf_eval.normalize import normalize


def test_casing_and_punctuation_are_ignored() -> None:
    assert normalize("Hey, can we push the STANDUP?") == normalize("hey can we push the standup")


def test_clock_times_match_their_spoken_form() -> None:
    assert normalize("push it to 11.30 tomorrow") == normalize("push it to eleven thirty tomorrow")
    assert normalize("at 11:30") == normalize("at eleven thirty")


def test_ordinals_match_their_spoken_form() -> None:
    assert normalize("the 15th of October") == normalize("the fifteenth of October")


def test_numbers_with_attached_units_match() -> None:
    assert normalize("from 400ms to 90ms") == normalize("from four hundred milliseconds to ninety milliseconds")


def test_am_pm_times_match() -> None:
    assert normalize("around 3 PM") == normalize("around three pm")
    assert normalize("at 3pm") == normalize("at three pm")
    assert normalize("at 11am") == normalize("at eleven am")


def test_plain_numbers_match_words() -> None:
    assert normalize("late by 15 minutes") == normalize("late by fifteen minutes")


def test_contractions_match_their_expansion() -> None:
    assert normalize("I've pushed it, we're done, I'll call") == normalize("I have pushed it we are done I will call")


def test_is_contractions_match_their_expansion() -> None:
    # Parakeet wrote "there is" where the speaker said "there's" (v2 ticket 07).
    assert normalize("there's time, here's what's left") == normalize("there is time here is what is left")
    assert normalize("where's he? who's here, he's and she's") == normalize("where is he who is here he is and she is")


def test_hyphenated_words_split() -> None:
    assert normalize("working end-to-end") == normalize("working end to end")


def test_devanagari_vowel_signs_survive() -> None:
    assert normalize("मैं आज थोड़ा देर से आऊंगा।") == ["मैं", "आज", "थोड़ा", "देर", "से", "आऊंगा"]


def test_thousands_separators() -> None:
    assert normalize("costs 1,000 rupees") == normalize("costs one thousand rupees")


def test_decimals_are_not_clock_times() -> None:
    assert normalize("version 2.5") == normalize("version two point five")


def test_a_half_matches_point_five() -> None:
    # Whisper and the number formatting write "1.5 seconds" for "one and a half seconds" (v2 ticket 07).
    assert normalize("about 1.5 seconds") == normalize("about one and a half seconds")
    assert normalize("twenty and a half") == normalize("20.5")
    assert normalize("an hour and a half") == ["an", "hour", "and", "a", "half"]


def test_minutes_with_a_leading_zero_read_as_oh() -> None:
    assert normalize("at 10.05") == normalize("at ten oh five")


def test_years_read_as_years() -> None:
    assert normalize("back in 1999") == normalize("back in nineteen ninety-nine")
