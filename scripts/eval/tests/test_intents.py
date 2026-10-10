from ovf_eval.intents import Expected, Parsed, score_intents


def expected(id: int, to: str, text: str) -> Expected:
    return Expected(id=id, app="slack", to=to, text=text)


def parsed(id: int, to: str, text: str, app: str = "slack") -> Parsed:
    return Parsed(id, {"action": "send_message", "app": app, "to": to, "text": text}, 0.9)


def test_a_matching_parse_passes_despite_number_and_spelling_differences() -> None:
    results = score_intents(
        [expected(24, "Gurjeet", "I'll be late by fifteen minutes.")],
        [parsed(24, "gurjeet", "I will be late by 15 minutes")],
    )

    assert results[0].ok and results[0].strict
    assert results[0].text_wer == 0


def test_a_wrong_pronoun_fails_strictly_even_though_it_is_close() -> None:
    # Turning reported speech into direct speech is the point of the model path.
    results = score_intents([expected(27, "Rohan", "The build is green and you can merge now.")],
                            [parsed(27, "Rohan", "The build is green and he can merge now.")])

    assert results[0].ok  # lenient: within 25%
    assert not results[0].strict


def test_names_must_match_exactly() -> None:
    results = score_intents([expected(25, "Meena", "Hi")], [parsed(25, "Mona", "Hi")])

    assert not results[0].ok and not results[0].strict
    assert "to" in results[0].reason


def test_the_wrong_app_fails() -> None:
    results = score_intents([expected(27, "Rohan", "The build is green.")], [parsed(27, "Rohan", "The build is green.", app="whatsapp")])

    assert not results[0].ok
    assert "app" in results[0].reason


def test_a_message_too_far_from_the_expected_text_fails() -> None:
    results = score_intents([expected(28, "Priya", "Lunch ke liye ready ho jao.")],
                            [parsed(28, "Priya", "Book a table for lunch at noon please")])

    assert not results[0].ok
    assert "text" in results[0].reason


def test_an_unknown_or_missing_parse_fails() -> None:
    results = score_intents([expected(26, "Gurjeet", "Main meeting mein hoon.")], [Parsed(26, None, 0.9)])

    assert not results[0].ok
    assert results[0].reason == "not understood"
    assert not score_intents([expected(26, "Gurjeet", "x")], [])[0].ok
