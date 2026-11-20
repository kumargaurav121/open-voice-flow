# Parakeet in English mode: the eval (2026-11-18/19)

**The question** (v2 ticket 07). English mode now runs NVIDIA Parakeet TDT 0.6B v2 in long parts, through the
app's own pipeline. Does it meet ticket 06's bar?
- Within **0.5 points** of Whisper turbo cut at pauses (English mode until now).
- **0.3 s or less** at release, at any length.
- Numbers come out as digits.

**Short answer: it misses the accuracy bar by 0.2 points (0.7 against 0.5).** The gap is the speaker's restarts,
which Parakeet writes as they were said and Whisper drops. It is about 4 times faster at release. On long
dictations it is both faster and more accurate. **The user chose go** (2026-11-19); restarts are ticket 19.

**What was tested.**
- **Parakeet v2** through `ParakeetTranscriber`, the app's provider. It ran in long parts, as the app does: cut
  only at a pause after 40 s of speech (`PauseCutter.Lengths.long`).
  - The model is the built-in manifest's: `FluidInference/parakeet-tdt-0.6b-v2-coreml` @
    `ee09c569f73759e6d44c9bd16766f477b2b36d39`, 21 files, 0.46 GB.
  - It was loaded from a scratch copy fetched with `fetch-model.py`. All 21 files match the SHA-256s in
    `BuiltInModels.parakeet`.
- **Whisper turbo**, compressed, as installed (ticket 18). It was cut at pauses, as English mode ran before.
- **Both runs used the app's text pipeline:**
  - the Latin-script guard
  - the rules cleanup, including numbers as digits
  - no dictionary unless stated
- **Both ran at speaking pace** (`--realtime`), so the time is from release to text.
- **Clips:** 36 English clips, 1,211 words.
  - The 17 from eval set 2 (604 words), recorded in one session on 2026-11-18.
  - 19 recorded for this ticket (607 words): items 45-58 and 60-64 of `docs/eval/reading-script-english.md`.
    They were recorded in one session on 2026-11-19. Item 59 wasn't read.
  - The new clips are ordinary dictation:
    - short messages, questions and updates of 4-15 s
    - three of 36-44 s
- **Machine:** M1 Pro.

## Accuracy (word errors, script-agnostic)

| Clips | Whisper, cut at pauses | Parakeet, long parts | Gap |
|---|---|---|---|
| The 17 eval-set clips | 6.5% | 7.3% | 0.8 |
| The 19 new clips | 5.8% | 6.3% | 0.5 |
| **All 36** | **6.1%** (75 errors) | **6.8%** (83 errors) | **0.7** (8 words; the bar is about 6) |
| The 17, with the dictionary | 6.6% (ticket 06's run) | 7.1% | 0.5 |
| Long dictation, 2.2 min (clips 35-37 joined, 328 words) | 4.9% | **4.6%** | -0.3 |
| Long dictation, 10.8 min (the same five times, 1,640 words) | 4.9% | **4.7%** | -0.2 |

Strict scores are the same within 0.1 points.

**Where the gap comes from:**
- **52 errors are the same in both.** They don't change the gap.
  - Mostly the reader said a word differently from the script: "slides from the review", "flight leaves",
    "half of the team", "update from today", "for a minute".
  - Some are names both models missed: Meera as "Mira", Vercel, Supabase.
  - The references were left as written.
- **Whisper alone: 23 errors.** "fixed 2 bucks" for "two bugs", "6:50" for "six fifteen", "just want a small
  change" for "just one small change", and it dropped words.
- **Parakeet alone: 31 errors, of which 11 are the speaker's restarts**, kept as said. Whisper drops them.

  | Clip | Restart |
  |---|---|
  | 6 | "next js. Next.js" |
  | 35 | "We also we are also" |
  | 51 | "the tw 28th" |
  | 58 | "dropped from the from about" |
  | 61 | "ship it to the team, to the beta group" |
  | 63 | "older lap laptops" |

  Without them, Parakeet has 72 errors (5.9%) against Whisper's 75 (6.1%).
- **The rest of Parakeet's errors:**
  - "Here Jun" for "Hey Arjun"
  - "main run" for "main branch"
  - "site" for "side"
  - "loads against" for "loads again"
  - "Gujeep" for "Gurjeet"
  - plurals dropped ("millisecond", "laptop")
- **Some scorer gaps are left in.** Each pair of forms below means the same, but is scored as an error:
  - "$2400" and "two thousand four hundred dollars": costs Whisper 1 word.
  - "4GB" and "four gigabytes": costs Whisper 4.
  - "12%" and "twelve percent": costs both 1.
  - "off site" and "offsite": costs Parakeet 2.

  Fixed, the gap would be about 0.9 points. That would not change the verdict, so they weren't fixed for this
  decision.
- **Two scorer gaps were fixed on the way,** with tests (`ovf_eval/normalize.py`). Before the fixes, Whisper lost
  3 words on the 17 clips. Ticket 06's report has a correction: its go rested on 7.3% against 6.5%, not 7.0%.
  - "there's" now matches "there is", and other `'s` contractions likewise.
  - "1.5" now matches "one and a half".

## Speed (release to text)

| | Whisper, cut at pauses | Parakeet, long parts |
|---|---|---|
| 36 clips: median, p95, slowest | 0.79 s, 1.31 s, 1.32 s | **0.19 s, 0.37 s, 0.53 s** |
| Long dictation, 2.2 min | 0.90 s | **0.11 s** |
| Long dictation, 10.8 min | 0.89 s | **0.18 s** |

- **Parakeet is about 4 times faster on clips up to 46 s.** It transcribes the whole dictation at release in one
  pass. No part is sent while speaking.
- **It is 5-8 times faster on long dictations.** It cut at a pause after each 40 s of speech, so only the last
  stretch was left at release.
- **The 0.3 s bar is missed on 3 of 36 clips** (0.33, 0.37 and 0.53 s), all under 46 s. Long dictations are
  under it.
- Whisper took 1.93 s and 2.48 s on the long dictations on 2026-11-18, against 0.90 s and 0.89 s here. Its time
  at release varies with the tail it has left. Parakeet took 0.14 s and 0.27 s then.

## Numbers

- **Parakeet's numbers on the 36 clips, after the rules:**
  - 10 and up as digits: "400", "90", "10", "25", "2400", "18,000", "11,000"
  - times: "11:30", "3:30", "6:15"
  - dates: "15th", "1st", "28th"
  - decimals and percentages: "1.5", "12%"
  - one to nine stay words: "three updates", "two bugs"
  - digits Parakeet wrote itself are kept: "4 gigabytes"
- **"six.15" was found and fixed.** Parakeet wrote the hour as a word and the minutes as digits. It now becomes
  "6:15", with a test, and clip 57 was rerun.
- **Code review found rules that went too far.** All are fixed with tests:
  - Rough counts became times or years: "five ten minutes" was "5:10 minutes", "twenty thirty people" was "2030
    people", "room two twelve" was "room 2:12". An hour and minutes are now a time only next to a time word:
    after "at", "by", "until" and the like, or before "tomorrow", "pm" and the like. "Ten oh five" counts as a
    time on its own.
  - "a thirty-second ad" was "a 32nd ad". An ordinal ending in "second" is now digits only next to a month.
  - "At one point two engineers left" was "At 1.2 engineers left".
- **Commands** (clips 24-28): Parakeet matches Whisper, 2/5 strict and 3/5 lenient (`p07-cmd-*`, `p07-final-cmd`).

## Supply chain

- **Model:** 21 data files at a pinned commit, each SHA-256-verified, credited to NVIDIA in the installed
  `ATTRIBUTION.md`. This is ADR 0010's amendment for v2 ticket 07.
- **FluidAudio** 0.18.3, no traits. The app calls only `AsrModels.loadLocal`, which reads one folder. Its
  downloaders are never called.
- **The built app** has no text-to-speech or diarization code, and none of the text-normalization binary's
  symbols.
- **Checked on the Mac after install (2026-11-20):**
  - The app downloaded the model and prepared both speech models in 39.6 s. All 21 installed files match their
    SHA-256s, at the pinned commit.
  - The eval runner ran the installed folder with networking denied (`sandbox-exec`, `deny network*`): clips 1,
    2 and 35 came out word for word as in `p07-final`.
  - FluidAudio's own folders (`~/Library/Application Support/FluidAudio`, `~/.cache/fluidaudio`) were never
    created.
  - Launched with English selected: "Speech model for english ready in 0.6s".
- **English dictations in the app (2026-11-20), three in all:**
  - **Speed:** release to text was 0.53 s with 5 s left at release, and 0.36 s and 0.43 s with 10-12 s left.
    Whisper turbo, in English mode on 2026-11-17, took 0.88-1.05 s with 2-2.5 s left and 1.34 s with 11 s left.
    Three earlier that morning took 2.5-4.7 s and are left out.
    - That is 2-3 times faster, on few dictations.
    - All three are over the 0.3 s bar, and slower than in the eval: about 0.2 s at similar lengths there.
  - **The first two came out wrong:**
    - "review of 33" for "review at three thirty"
    - "from 12:12 value percent to invoice counts" for "by twelve percent, and the invoice comes"
  - **The rules weren't the cause.** Given the words that were said, they write "at 3:30" and "12%". Parakeet
    heard other words.
  - **The audio wasn't kept,** so it couldn't be replayed. The mic input had changed nine times that morning.
  - **The numbers sentence was said again 50 minutes later.** It came out right: "Our sign up rate went up by
    12% and the invoice comes to 2400 dollars." The default input was the MacBook Pro microphone afterwards; the
    mic for each dictation isn't known.
  - **1 of 3 came out right.** The "three thirty" sentence wasn't tried again.
  - **Not tested yet:** Parakeet against Whisper on the same audio recorded by the app. If English dictations
    keep coming out wrong:
    1. Turn on Settings → Privacy → Keep audio recordings.
    2. Run both models on the kept recordings with `EvalRunner --clips`.

    Ticket 20 tracks this.

## Decision (user, 2026-11-19): go, below the bar

- **Why:**
  - The gap is restarts, which ticket 19 addresses. Otherwise Parakeet's recognition is level with Whisper's.
  - It is about 4 times faster at release.
  - On long dictations it is more accurate and 5-8 times faster.
- **Not met:**
  - Within 0.5 points: 0.7.
  - 0.3 s or less at any length: 3 of 36 clips over, slowest 0.53 s. On the Mac, all 3 dictations were over
    (0.36-0.53 s).

Runs:
- 17 eval-set clips: `p07-turbo-rt`, `p07-final` (and `p07-v2-long`, before the number rules), and with
  `-dict`.
- 19 new clips: `p07b-turbo-rt`, `p07b-v2-long` (`p07b-v2-57` after the "six.15" fix).
- Pooled: `p07all-turbo-rt`, `p07all-v2-long`.
- Long dictations (scratch clips folder): `long-turbo`, `long-v2`.

```sh
# The 19 new clips: split the recording, then run both models at speaking pace
scripts/eval/split.py docs/eval/raw/english/reading-english-20261119.m4a --ids 45-58,60-64 --pad 0.4 \
    --segments docs/eval/segments/reading-english-20261119.json
swift run -c release EvalRunner --name p07b-turbo-rt --language english --realtime --ids 45,46,...,58,60,...,64
swift run -c release EvalRunner --name p07b-v2-long --language english --realtime --ids 45,...,64 \
    --stt parakeet-v2 --parakeet-folder <verified copy>
cd scripts/eval && uv run ovf-eval score p07all-turbo-rt p07all-v2-long
```
