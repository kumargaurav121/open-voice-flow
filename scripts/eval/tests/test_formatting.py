from ovf_eval.formatting import ExpectedFormat, FormatResult, score_formatting
from ovf_eval.score import Transcript


def result(expected: str, actual: str) -> FormatResult:
    return score_formatting([ExpectedFormat(1, expected)], [Transcript(1, actual, 1.0)])[0]


def check(expected: str, actual: str) -> bool:
    return result(expected, actual).exact


def test_case_and_spacing_differences_still_match() -> None:
    assert check("Hi Rohan,\nThanks for the update.", "hi rohan,  \n   thanks for  the update.  ")


def test_a_lost_line_break_fails() -> None:
    assert not check("Hi Rohan,\nThanks for the update.", "Hi Rohan, Thanks for the update.")


def test_missing_punctuation_fails() -> None:
    assert not check("Kal market se yeh cheezein laani hain:\n1. Doodh\n2. Bread",
                     "Kal market se yeh cheezein laani hain\n1. Doodh\n2. Bread")


def test_any_number_of_blank_lines_is_one_paragraph_break() -> None:
    assert check("Thanks for the update.\n\nLet's ship it on Friday!",
                 "Thanks for the update.\n\n\n\nLet's ship it on Friday!\n")


def test_a_paragraph_break_is_not_a_line_break() -> None:
    assert not check("Thanks for the update.\n\nLet's ship it on Friday!",
                     "Thanks for the update.\nLet's ship it on Friday!")


def test_a_clip_without_a_transcript_fails_instead_of_being_skipped() -> None:
    results = score_formatting([ExpectedFormat(40, "Let's meet at five."), ExpectedFormat(41, "Meeting chaar baje hai.")],
                               [Transcript(40, "Let's meet at five.", 1.0)])

    assert [(r.id, r.exact, r.actual) for r in results] == [(40, True, "Let's meet at five."), (41, False, None)]


def test_a_miss_shows_how_close_it_was() -> None:
    [near, far] = score_formatting(
        [ExpectedFormat(40, "Let's meet at five, at the usual coffee place."), ExpectedFormat(44, "I enjoyed it.")],
        [Transcript(40, "Let's meet at four, actually no, let's make it five, at the usual coffee place.", 1.0),
         Transcript(44, "Completely different words here.", 1.0)],
    )

    assert not near.exact and not far.exact
    assert 0 < far.similarity < near.similarity < 1


def test_words_ignore_spelling_variants_and_number_forms() -> None:
    assert result("Main zyada der se aaunga, meeting five baje hai.", "main jyada der se aunga meeting 5 baje hai").words_wer == 0


def test_words_count_a_self_correction_left_in() -> None:
    kept = result("Let's meet at five, at the usual coffee place.",
                  "Let's meet at 4, actually no, let's make it 5 at the usual coffee place.")

    assert kept.words_wer > 0.5


def test_layout_is_lines_paragraphs_and_list_numbers_not_sentence_punctuation() -> None:
    assert result("I actually enjoyed the demo, the animation is smooth.",
                  "I actually enjoyed the demo. The animation is smooth.").layout_ok
    assert not result("Three updates:\n1. Login is fixed.\n2. Notes are ready.",
                      "Three updates: 1. Login is fixed, 2. Notes are ready.").layout_ok
    assert not result("Thanks.\n\nShip it!", "Thanks.\nShip it!").layout_ok
