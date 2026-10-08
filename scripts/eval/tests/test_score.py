import pytest

from ovf_eval.score import Item, Transcript, score


def item(id: int, lang: str, reference: str, devanagari: str | None = None) -> Item:
    return Item(id=id, lang=lang, reference=reference, reference_devanagari=devanagari)


def test_perfect_transcripts_score_zero() -> None:
    items = [item(1, "en", "Hey, can we push the standup?"), item(2, "hinglish", "Bhai demo ready hai")]
    transcripts = [Transcript(1, "hey can we push the standup", 0.5), Transcript(2, "bhai demo ready hai", 0.5)]

    report = score(items, transcripts)

    assert report.overall.strict_wer == 0
    assert report.overall.agnostic_wer == 0


def test_wer_is_corpus_level_errors_over_reference_words() -> None:
    # en: 1 substitution in 4 words; hi: perfect, 2 words. Overall 1 / 6.
    items = [item(1, "en", "send the invoice now"), item(2, "hi", "khaana taiyaar")]
    transcripts = [Transcript(1, "send the inverse now", 1.0), Transcript(2, "khaana taiyaar", 1.0)]

    report = score(items, transcripts)

    assert report.by_language["en"].strict_wer == pytest.approx(0.25)
    assert report.by_language["hi"].strict_wer == 0
    assert report.overall.strict_wer == pytest.approx(1 / 6)
    assert report.overall.reference_words == 6


def test_deletions_and_insertions_count_as_errors() -> None:
    items = [item(1, "en", "one two three four")]
    transcripts = [Transcript(1, "one three four five", 1.0)]

    assert score(items, transcripts).overall.strict_wer == pytest.approx(0.5)


def test_devanagari_output_is_wrong_strictly_but_right_script_agnostically() -> None:
    items = [item(1, "hi", "Main aaj thoda der se aaunga")]
    transcripts = [Transcript(1, "मैं आज थोड़ा देर से आऊंगा", 1.0)]

    report = score(items, transcripts)

    assert report.overall.strict_wer == 1
    assert report.overall.agnostic_wer == 0


def test_devanagari_references_can_be_used_for_pure_hindi_items() -> None:
    items = [item(1, "hi", "Main aaj der se aaunga", devanagari="मैं आज देर से आऊंगा।"), item(2, "en", "on time")]
    transcripts = [Transcript(1, "मैं आज देर से आऊंगा", 1.0), Transcript(2, "on time", 1.0)]

    assert score(items, transcripts, devanagari_references=True).overall.strict_wer == 0


def test_latency_median_and_p95_use_nearest_rank() -> None:
    items = [item(i, "en", "word") for i in range(1, 21)]
    transcripts = [Transcript(i, "word", float(i)) for i in range(1, 21)]

    report = score(items, transcripts)

    assert report.latency_median == pytest.approx(10.5)
    assert report.latency_p95 == 19.0


def test_translated_clips_are_listed() -> None:
    items = [
        item(14, "hinglish", "Maine PR raise kar diya hai, bas ek baar review kar lo."),
        item(20, "hinglish", "Weekend pe plan kya hai? Chalo kahin bahar chalte hain."),
        item(21, "en", "I wanted to give a quick update."),
    ]
    transcripts = [
        Transcript(14, "I Raced this team. Just only give this one question.", 1.0),
        Transcript(20, "वीकेंड पर प्लान क्या है चलो कहीं बहर चलते हैं", 1.0),
        Transcript(21, "Something entirely different here.", 1.0),
    ]

    assert score(items, transcripts).translated == [14]


def test_language_with_no_reference_words_scores_zero_instead_of_crashing() -> None:
    report = score([item(1, "en", "...")], [Transcript(1, "", 1.0)])

    assert report.overall.strict_wer == 0
