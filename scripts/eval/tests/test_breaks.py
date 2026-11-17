from ovf_eval.breaks import Breaks, score_breaks
from ovf_eval.score import Item, Transcript


def breaks(reference: str, hypothesis: str) -> Breaks:
    return score_breaks([Item(1, "hinglish", reference)], [Transcript(1, hypothesis, 1.0)])


def test_matching_sentence_breaks_count_as_found() -> None:
    result = breaks("We shipped the fix. Then we tested it.", "we shipped the fix. then we tested it.")

    assert (result.found, result.false, result.missed) == (1, 0, 0)


def test_a_break_inside_a_sentence_is_false() -> None:
    result = breaks("Rohan ne kal raat PR merge kar diya tha.", "Rohan ne. Kal raat PR merge kar diya tha.")

    assert (result.found, result.false, result.missed) == (0, 1, 0)


def test_a_sentence_run_into_the_next_is_missed() -> None:
    # Spelling variants still line up: jyada/zyada, aunga/aaunga.
    result = breaks("Main zyada der se aaunga. Kal milte hain.", "main jyada der se aunga kal milte hain")

    assert (result.found, result.false, result.missed) == (0, 0, 1)


def test_question_and_exclamation_marks_are_breaks_too() -> None:
    result = breaks("Weekend pe plan kya hai? Chalo kahin bahar chalte hain!", "weekend pe plan kya hai. chalo kahin bahar chalte hain")

    assert (result.found, result.false, result.missed) == (1, 0, 0)


def test_the_end_of_the_text_is_not_counted() -> None:
    result = breaks("Ship it today.", "ship it today")

    assert (result.found, result.false, result.missed) == (0, 0, 0)
