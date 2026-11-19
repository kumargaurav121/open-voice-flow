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

New recording? Split it first with `split.py`, naming the items it holds:
`scripts/eval/split.py docs/eval/raw/reading-YYYYMMDD.m4a --ids 1-28` (see `docs/eval/reading-script.md`). Items
29-44 (`docs/eval/reading-script-long.md`: long dictations and formatting cases) come from a second recording,
cut with `--ids 29-44 --min-silence 2.8 --pad 0.4 --segments docs/eval/segments/reading-long-20261113.json`.
Baseline: `docs/eval/reports/2026-11-13-eval-set-2-baseline.md`. `ovf-eval score` compares runs on the clips
every run transcribed, so runs from before the set grew still compare.

**Sentence breaks**: `uv run ovf-eval breaks <run> ...` counts full stops, question and exclamation marks found,
false (output only) and missed (reference only), lining output words up with the reference. Word error rate
can't see these (v2 ticket 02: cuts mid-sentence).

**Formatting** (items 38-44): `uv run ovf-eval format <run>` compares each item's final text with its
`expected_output`: exact (ignoring case and spacing), word errors against the expected text, and layout
(lines, paragraph breaks, list numbers).

**Commands** (ticket 11): `swift run -c release EvalRunner --name app-commands --model-folder <path> --commands`
runs clips 24-28 through the command parser and writes `<name>.intents.json`; `uv run ovf-eval intents
app-commands` scores them against `expected_parse` (strict: exact words; lenient: within 25% WER).

**Parakeet** (English mode's model, ADR 0013): `swift run -c release EvalRunner --name p07-v2 --language english
--realtime --stt parakeet-v2` runs it from the app's installed folder, in long parts as the app does (cut only at a
pause after 40 s of speech); `--parakeet-folder <path>` loads another copy, and `parakeet-v3` the multilingual
model. Fetch a model that isn't in the built-in manifests with `fetch-model.py <repo> <commit> <dest> <patterns>`:
pinned commit, allow-listed data files only, each verified against the commit's hashes (ADR 0010, amendment for v2
ticket 06). See `docs/eval/reports/2026-11-18-parakeet-english.md` and `2026-11-18-parakeet-in-english-mode.md`.

**Scores.** WER is corpus-level (total edits / total reference words) after normalising case,
punctuation, contractions and numbers ("11.30" = "eleven thirty"). *Agnostic* WER also treats a
Hindi word in Devanagari and its romanisation as the same word, so it measures what the model heard;
*strict* WER is the raw text before cleanup. A non-English clip sharing under 30% of its reference
words with the output is flagged as translated.

The optional cleanup step (scoring STT + LLM cleanup together) arrives with ticket 05.
