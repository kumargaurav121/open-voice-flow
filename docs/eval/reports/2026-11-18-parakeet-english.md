# Parakeet for English mode: the test (2026-11-18)

**The question** (v2 ticket 06). Should English mode move from Whisper turbo to NVIDIA Parakeet? Parakeet reads
a whole clip in one pass, with no 30-second window and no word-by-word decoding. The bar: **go** if it's within
0.5 points of the English model's accuracy and clearly faster.

**What was tested.**

| Model | Source, pinned | On disk | License |
|---|---|---|---|
| Whisper turbo, compressed (today's English model) | as installed (ticket 18) | 0.65 GB | MIT |
| Parakeet TDT 0.6B v2 (English) | `FluidInference/parakeet-tdt-0.6b-v2-coreml` @ `ee09c569f73759e6d44c9bd16766f477b2b36d39` | 0.44 GB | CC-BY-4.0 |
| Parakeet TDT 0.6B v3 (25 languages, no Hindi) | `FluidInference/parakeet-tdt-0.6b-v3-coreml` @ `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe` | 0.46 GB | CC-BY-4.0 |

- **Weights:** FluidInference's Core ML builds, ungated.
  - The publisher is the FluidAudio maintainers' own conversion org. The model cards name NVIDIA's models as
    the base. The repos hold no code files, and have about 0.13M (v2) and 3.2M (v3) downloads.
  - Prebuilt Core ML from a third party is outside ADR 0010's "convert ourselves". It was allowed here for
    evaluation only: ADR 0010's amendment for this ticket.
  - Only the four compiled models and the vocabulary were fetched: Preprocessor, Encoder (v3's default
    one), Decoder, JointDecision (v3: `JointDecisionv3`), and `parakeet_vocab.json`.
  - `scripts/eval/fetch-model.py` verified every file against the pinned commit's own hashes.
  - They went into a scratch folder, not the app's models folder.
- **Library:** FluidAudio 0.18.3 (Apache-2.0), pinned exactly, with commit `c8b41f98` in `Package.resolved`.
  - The eval runner loads Parakeet with `AsrModels.loadLocal`, which reads one folder and never downloads.
  - The runner uses the app's own text pipeline: `--stt parakeet-v2|parakeet-v3 --parakeet-folder <path>`.
- **No hidden downloads:**
  - Both models were run with networking denied (`sandbox-exec`, `deny network*`) on clips 1, 2 and 35.
    They transcribed them exactly as the scored runs did.
  - FluidAudio's own model folders (`~/Library/Application Support/FluidAudio`, `~/.cache/fluidaudio`) were
    never created.
- **FluidAudio's optional parts:**
  - The package is added with no traits, so its text-to-speech, diarization and text-normalization extras
    are off.
  - The text-to-speech and diarization engines aren't compiled in. Only FluidAudio's table of model names
    mentions them.
  - SwiftPM still downloads the text-normalization binary (`NemoTextProcessing.xcframework`, a Rust static
    library, checksum-pinned in FluidAudio's manifest) when it resolves packages. It isn't linked: none of
    its symbols are in the runner.

**Conditions.**
- The 17 English clips: 603 words, 5-46 s each.
- English mode, no dictionary unless stated.
- One session on the M1 Pro, on battery, Low Power Mode off.
- Turbo ran first and again after Parakeet: 8.6% both times, median 0.92 s and 0.87 s, the same as ticket
  18's `enc-632` (8.6%, 0.92 s).
- Two ways of dictating:
  - **Whole clip:** transcribed once, on release.
  - **Cut at pauses:** the app's way since ticket 02. The clip plays at speaking pace and parts are
    transcribed while it plays, so the time is from release to text.

## Accuracy (word errors)

| Model | Whole clip | Cut at pauses | Whole clip, dictionary | Cut at pauses, dictionary |
|---|---|---|---|---|
| Whisper turbo | 8.6% | **7.0%** | 8.6% | **7.1%** |
| Parakeet v2 | **7.3%** | 8.1% | **7.1%** | 8.0% |
| Parakeet v3 | 8.0% | 8.3% | 7.8% | — |

The table shows script-agnostic word errors. Strict scores are the same, except Parakeet v3 is 0.1-0.2 points
higher. The dictionary is the one from the October eval: Gurjeet, Priya, Rohan, Supabase, Vercel, Next.js,
WhisperKit, MLX Swift, Qwen, Figma.

> **Correction (2026-11-19, ticket 07).** The scorer counted two correct forms as errors: "there's" against
> "there is", and "1.5" against "one and a half". Whisper wrote both, so it lost 3 words. Both are fixed,
> with tests (`ovf_eval/normalize.py`). Rescored:
> - Whisper cut at pauses: **6.5%**, not 7.0%. With the dictionary, 6.6%, not 7.1%.
> - Parakeet v2 whole: unchanged, 7.3% (7.1% with the dictionary).
> - v2 cut at pauses with the dictionary 7.9%, v3 whole 7.9%; the rest unchanged.
>
> So the go below rested on a **0.8-point gap**, not 0.3: outside the 0.5-point bar. Ticket 07 re-checked
> it on 19 more English clips: `2026-11-18-parakeet-in-english-mode.md`.

- **Each model works best a different way.**
  - **Whisper is better cut at pauses.** Whole, it skips phrases in long clips: "seconds are left at the
    end" (35), "if we cut in the" (37).
  - **Parakeet is better whole.** On short parts it loses context: "the notch" became "to launch" (21) and
    "Diwali" became "Diary" (23).
- **The comparison that matters is each model the way it would run.**
  - That means Parakeet v2 whole against Whisper cut at pauses: 7.3% against 7.0%, and 7.1% each with the
    dictionary.
  - That is within the 0.5-point bar.
  - With 603 words, the 0.3-point gap is 2 words.
- **v3 is worse than v2 on English** in every column, and its extra languages don't include Hindi.

## Speed

| Model | Whole clip: median, p95 | Cut at pauses: median, p95 | Clips 35-44 (a real tail at release) |
|---|---|---|---|
| Whisper turbo | 0.92 s, 2.92 s | 0.50 s, 1.27 s | 0.78-1.27 s |
| Parakeet v2 | **0.09 s, 0.29 s** | 0.00 s, 0.24 s | **0.08-0.29 s whole**, 0.11-0.24 s cut |
| Parakeet v3 | 0.09 s, 0.28 s | 0.00 s, 0.33 s | 0.07-0.28 s whole |

- **Parakeet v2 is 10 times faster on a whole clip.** It reads a 46-second dictation in 0.29 s, so dictations
  up to about a minute don't need transcribing while you speak. Longer ones do; see below.
- **The release-to-text column flatters cutting at pauses.**
  - Clips 1-23 end with enough silence for the app to cut there and finish before the "release", so these
    clips show 0.0-0.5 s for both models.
  - Clips 35-44 have a real tail to transcribe at release. The cut-at-pauses time also includes trimming and
    pasting; the whole-clip time doesn't.
  - There, Parakeet v2 whole takes 0.08-0.29 s and Whisper cut at pauses takes 0.78-1.27 s, about 5 times
    longer.
  - Turbo's range is from one run. With the dictionary it reached 2.79 s on clip 42.
- **Long dictations are slower on release** (hands-free runs up to 10 minutes). Clips 35-37 were joined into
  2.2 and 10.8 minutes, Parakeet v2, whole clip, two runs each:
  - **2.2 minutes:** 1.82-2.08 s.
  - **10.8 minutes:** 5.42-7.67 s.
  - The 46-second clips took 0.29 s, so time grows faster than the audio from a minute or so.
  - No words were lost where FluidAudio's 15-second windows join. Word errors were 4.9% and 5.0%, the same
    speech's rate as separate clips.
  - Whisper cut at pauses has only the tail left at release, about 1 s at any length.
- **Loading:**
  - First load (the one-time Neural Engine compile): 29 s for each Parakeet model. Turbo took 303 s in this
    runner and 5 minutes in the app (ticket 18).
  - Later loads: 0.3-0.4 s, against 3.2 s for turbo.

## Errors worth knowing

- **Numbers mostly come out as words.**
  - v2: "four hundred millisecond", "eleven thirty", "one and a half seconds".
  - Turbo: "400ms", "11:30", "1.5 second".
  - Both Parakeet models also write some numbers as digits: v2 wrote "1st of December" and "10 laptops"
    (36); v3 wrote "400 millisecond" next to "ninety" (4).
  - The score treats both forms as the same, but a user would see the words. Parakeet also dropped the
    plural in "milliseconds" twice (4).
- **Names:**
  - Supabase was wrong everywhere: Parakeet "superbus", turbo "super-piece" or "super biz".
  - Vercel was wrong everywhere except turbo whole with the dictionary, which fixed "VERSEL". Parakeet wrote
    "Warsaw"; turbo cut at pauses wrote "worsen".
  - Gurjeet: Parakeet v2 got it right in clip 3. In clip 8 it wrote "Gujeep", and the dictionary didn't fix
    it; turbo got both right.
  - v3 also wrote "Prayer" for Priya and "Rowan" for Rohan.
  - The dictionary fixed "Whisper Kit" for Parakeet, but not for turbo, which wrote "Super, Whisper, Kit".
- **Stumbles are kept.**
  - Parakeet writes what was said, including the reader's restarts: "next js. Next.js" (6), "We also we are
    also" (35).
  - Whisper drops them. Here that cost Parakeet 4 words.
- **Spoken punctuation stays as words.**
  - Parakeet kept "comma … exclamation mark" as words (42), as read.
  - Turbo turned "comma" and "exclamation mark" into marks, kept "new line" and "full stop" as words, and
    wrapped the clip in quotation marks.
  - Words are what spoken punctuation (ticket 09) expects.
- **Sentence breaks** (found / false / missed, `ovf-eval breaks`):
  - Whole clip: turbo 20 / 5 / 1, Parakeet v2 20 / 4 / 3, v3 20 / 5 / 2.
  - Cut at pauses, every model loses breaks: turbo 14 / 5 / 8, v2 12 / 4 / 11.
  - So transcribing whole clips also avoids the problem ticket 17 addresses, for English.
  - On whole clips Parakeet punctuates about as well as Whisper.

## Decision (user, 2026-11-18): go, Parakeet v2, in long parts

- **Why:**
  - Parakeet v2 transcribing whole clips is within the bar: 7.3% against 7.0%, and equal with the
    dictionary. (With the scorer fixed, 7.3% against 6.5%: see the correction under Accuracy.)
  - It is clearly faster: 0.08-0.29 s against 0.78-1.27 s at release.
- **Not v3.**
- **The margin is small.** Against Whisper cut at pauses the gap is 2 words, against a bar of 3, from single
  runs. Like for like, Parakeet wins on whole clips and loses cut at pauses. The go therefore depends on
  Parakeet getting long stretches of speech, not short parts.
- **Long parts.** The go was first given for whole clips. After the long-dictation result (above), the user
  chose this:
  - Parakeet transcribes while you speak, but cuts only at a pause after about 40 s of speech.
  - Each part keeps its context, and release has at most about 40 s left: 0.3 s or less at any length.
  - This is untested. Ticket 07 measures it and re-checks the 0.5-point bar.
- **Changes this makes to ticket 07:**
  - English mode cuts at pauses only after about 40 s of speech. Shorter dictations are a single part.
  - Numbers need formatting as digits, from mixed output, either with our own rules or FluidAudio's text
    normalization. The latter is the prebuilt binary noted above.
  - Shipping FluidInference's prebuilt build needs an ADR 0010 exception, as Argmax's turbo had, or a
    conversion of our own.

Runs: `p06-turbo-whole-a`, `p06-turbo-whole-b`, `p06-v2-whole`, `p06-v3-whole`, `p06-turbo-rt`, `p06-v2-rt`,
`p06-v3-rt`, and each with `-dict` where shown; no-network checks `p06-offline-v2`, `p06-offline-v3`; long
dictations `long-v2`, `long-v2-b` (clips 35-37 joined once and five times, in a scratch clips folder).

```sh
# Fetch both models (verified), then for each: --whole, or --realtime for cutting at pauses
python3 -I scripts/eval/fetch-model.py FluidInference/parakeet-tdt-0.6b-v3-coreml \
    7dd20fe6b1797d35f5e3307e8b1732d9a178edfe ~/parakeet-v3 'Preprocessor.mlmodelc/*' 'Encoder.mlmodelc/*' \
    'Decoder.mlmodelc/*' 'JointDecisionv3.mlmodelc/*' parakeet_vocab.json
swift run -c release EvalRunner --name p06-v2-whole --language english --whole \
    --ids 1,2,3,4,5,6,7,8,21,23,35,36,37,39,40,42,44 --stt parakeet-v2 --parakeet-folder ~/parakeet-v2
```
