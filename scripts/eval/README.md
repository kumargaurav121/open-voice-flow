# Eval tooling

Scores speech-to-text on the personal eval set (`docs/eval/`). Recordings and transcripts stay
local (git-ignored); only references, segment timings and score reports are committed.

```sh
cd scripts/eval
uv sync --extra models                 # model runners (MLX, PyTorch); skip if only scoring
uv run ovf-eval run turbo-auto         # transcribe the clips with one config
uv run ovf-eval score --all            # compare every config with saved transcripts
uv run ovf-eval score --all --report ../../docs/eval/reports/$(date +%F)-bakeoff.md
uv run pytest && uv run mypy ovf_eval tests
```

New recording? Split it first with `split.py` (see `docs/eval/reading-script.md`).

**Scores.** WER is corpus-level (total edits / total reference words) after normalising case,
punctuation, contractions and numbers ("11.30" = "eleven thirty"). *Agnostic* WER also treats a
Hindi word in Devanagari and its romanisation as the same word, so it measures what the model heard;
*strict* WER is the raw text before cleanup. A non-English clip sharing under 30% of its reference
words with the output is flagged as translated.

The optional cleanup step (scoring STT + LLM cleanup together) arrives with ticket 05.
