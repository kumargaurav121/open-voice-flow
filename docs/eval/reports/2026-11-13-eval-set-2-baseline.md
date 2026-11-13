# Eval set 2: baseline before the v2 changes (2026-11-13)

**Purpose.** This is the reference that every v2 change is measured against: transcribing while you speak,
the compressed Hinglish model, Parakeet for English, and formatting.

**What's new in the eval set.** Items 29-44, read from `docs/eval/reading-script-long.md`:

| Items | What they are | Length each |
|---|---|---|
| 29-34 | Long Hinglish | 35-49 s |
| 35-37 | Long English | 36-46 s |
| 38-44 | Formatting cases | 6-14 s |

**How the clips were made.**
- One recording, `reading-long-20261113.m4a`, cut by `scripts/eval/split.py` at pauses longer than 2.8 s, with 0.4 s of padding.
- The segments are committed in `docs/eval/segments/reading-long-20261113.json`.
- Each cut was checked against its script item by transcribing it.
- References are the words as read. Items 38-44 also carry `expected_output`, the text as it should look once formatted.

## Accuracy

**The runs used.** Both use the app's pipeline with no dictionary.

| Model | Clips 1-28 | Clips 29-44 |
|---|---|---|
| Hinglish model (Oriserve on the Neural Engine) | `app-oriserve-ane` (October) | `baseline-oriserve` |
| English model (Whisper turbo, English forced) | `app-turbo-en-nodict` (October) | `baseline-turbo-english` |

Word error rate. The Hinglish model's figures are script-agnostic / strict; the English model's two
measures are equal on these clips.

| Clips | Hinglish model | English model |
|---|---|---|
| Hinglish long, 29-34 (604 words) | 14.6% / 24.2% | — |
| English long, 35-37 (327 words) | 8.3% / 8.6% | 8.0% |
| English, old set (10 clips, 194 words) | 19.1% / 20.1% | 7.7% |
| English, new set (7 clips, 409 words) | 8.6% / 8.8% | 8.1% |
| **English, all 17 clips (603 words)** | **11.9% / 12.4%** | **8.0%** |

**What this shows:**
- **The English model is better on English overall.** The gap is mostly on short sentences; on long English the two models are close. This supports making English the default (v2 ticket 08).
- **Recurring errors:**
  - Both models wrote "blocked" as "blogged" (39).
  - The Hinglish model wrote "launch" as "lunch" (43). The English model wasn't run on that Hinglish item.
  - The Hinglish model writes "yah" for "yeh" and "tin" for "teen". The scorer's spelling rules count these as different words, which is most of the gap between its strict and script-agnostic figures.

## Formatting (items 38-44)

Run with `ovf-eval format <run>`. Three measures:
- **Exact:** the text equals the expected output, ignoring case and spacing.
- **Words WER:** word errors against the expected output, with spelling variants and number forms counted as the same word.
- **Layout:** the lines, paragraph breaks and list numbers match.

| Clip | Case | Hinglish model: words, layout | English model: words, layout |
|---|---|---|---|
| 38 | list ("first… second…", Hinglish) | 53%, FAIL | not run (Hinglish) |
| 39 | list ("one… two…") | 12%, FAIL | 12%, FAIL |
| 40 | self-correction ("actually no") | 70%, pass | 70%, pass |
| 41 | self-correction ("nahi nahi", "sorry") | 100%, pass | not run (Hinglish) |
| 42 | spoken punctuation, "new line", "new paragraph" | 67%, FAIL | 50%, FAIL |
| 43 | fillers and stutters | 43%, pass | not run (Hinglish) |
| 44 | "actually" that must stay | 0%, pass | 0%, pass |

**Totals:**
- Hinglish model: exact 0/7, layout 4/7.
- English model: exact 0/4, layout 2/4. It ran only the 4 English items.

**What fails and why:**
- **Spoken punctuation is typed as words:** "comma new line … full stop, new paragraph".
- **Lists:** the Hinglish model numbered item 39 inline ("three updates: 1. … 2. …") but kept it on one line.
- **Fillers:** only um/uh are removed, by the rules cleanup. "basically", "matlab" and the repeated "agar agar" remain.
- **Self-corrections** are left in: the high word error on 40 and 41 is the abandoned words.
- **Item 44:** the words come out right. It misses exact only because the model wrote a full stop where the script had a comma.

## Speed

**The speed baseline is the app's own log, not the runner.**
- **The log:** 132 real dictations, 8 October to 5 November 2026.
- **The timing:** from releasing `fn` to the text being in place (transcription plus insertion).
- **AI cleanup** was off except for three dictations on 8 October.

| Time `fn` was held | Dictations | Median release → text |
|---|---|---|
| under 5 s | 66 | 1.13 s |
| 5-10 s | 29 | 1.49 s |
| 10-20 s | 18 | 1.82 s |
| 20-40 s | 12 | 2.65 s |
| 40 s or more | 7 | 4.26 s |
| **all** | **132** | **1.43 s (p90 3.00 s, nearest rank)** |

**The eval runner's timings today don't match the app, and the cause isn't known.**
- **What we saw:**
  - The encoder took about 1.7-1.9 s per 30-second window, for both models, in every run today.
  - In October, the same runner on the same model took 0.82-0.85 s in total for each of clips 1-3. The app's last long dictation (5 November) encoded at 0.61 s per window.
- **Ruled out:**
  - A macOS update (installed in September).
  - Heat and Low Power Mode.
  - The app competing for the Neural Engine (it wasn't running).
  - The runner build: an October build and two fresh ones behave the same.
- **Observed at the same time:**
  - macOS media analysis (`mediaanalysisd`) running at 68-100% CPU. It uses the Neural Engine.
  - `ANECompilerService` starting with the first model load of the day. That load took 46 s; later loads took about 2 s.
- **Not established:** the encoder time stayed steady whatever media analysis was doing, which suggests the encoder ran off the Neural Engine rather than sharing it.
- **Rule until this is explained:**
  - Compare runner timings only within one session, after re-timing clips 1-3 against October's 0.82-0.85 s.
  - Speed claims for the app come from the app log.

**For reference only:** two runs of the Hinglish model on 29-34 today gave medians of 8.6 s and 5.8 s; the
English model on 35-37 gave 5.3 s and 5.1 s.

## Reproducing

```sh
python3 scripts/eval/split.py docs/eval/raw/long/reading-long-20261113.m4a --ids 29-44 --min-silence 2.8 --pad 0.4 \
    --segments docs/eval/segments/reading-long-20261113.json
swift build -c release --product EvalRunner
.build/release/EvalRunner --name baseline-oriserve --model-folder ~/Library/Application\ Support/open-voice-flow/models/oriserve-hinglish --ids 29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44
.build/release/EvalRunner --name baseline-turbo-english --language english --ids 35,36,37,39,40,42,44
cd scripts/eval
uv run ovf-eval score baseline-oriserve                         # 29-44, Hinglish model
uv run ovf-eval score app-oriserve-ane app-turbo-en-nodict      # 1-28, both models (October runs)
uv run ovf-eval format baseline-oriserve
uv run ovf-eval format baseline-turbo-english
```

**How the CLI's columns relate to the tables above:**
- The `score` command groups clips by language, not by item range.
- Its `hinglish` column for `baseline-oriserve` covers 29-34 plus the Hinglish formatting items 38, 41 and 43 (669 words, also 14.6%).
- Its `en` column covers the 7 English items of the new set.
- The per-group rows in the Accuracy table score each item range on its own.

The runner builds its text pipeline with `TranscriptPipeline`, the same as the app, so its transcripts are
what the app would paste into a non-code app.
