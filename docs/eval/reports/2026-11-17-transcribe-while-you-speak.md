# Transcribe while you speak: accuracy and speed (2026-11-17)

**What changed (v2 ticket 02, ADR 0012).**
- The live audio is cut at the speaker's pauses (0.5 s or more) and each finished part is transcribed in the background.
- At release only the tail is left. When the speaker paused before letting go, nothing is left.
- The parts' text is joined: under a 1 s pause, a cut is taken as mid-sentence and Whisper's full stop is removed.
- English letters, the dictionary and cleanup then run once on the whole text.

**How it was measured.**
- The eval runner now plays each clip into the app's own push-to-talk session, so it cuts exactly as the app does.
- `--whole` transcribes each trimmed clip in one go, the way the app worked before.
- `--realtime` plays the audio at speaking pace and times release to text.
- No dictionary, no AI cleanup.

## Accuracy: within the bar on every group

Word error rate, script-agnostic / strict:

| Clips | Whole | With cuts |
|---|---|---|
| **Hinglish model, all 44 clips** | 14.0% / 19.7% | **13.6% / 19.2%** |
| English clips (636 words) | 11.5% | 11.8% |
| Hinglish clips (827 words) | 16.2% | 15.2% |
| Long clips 29-37 (931 words) | 12.4% / 18.7% | 11.5% / 17.5% |
| Clips cut into two or more parts (1,070 words) | 13.8% / 19.7% | 13.3% / 19.0% |
| Clips cut once or not at all (436 words) | 14.4% / 19.7% | 14.4% / 19.7% |
| **English model, 17 English clips** | 7.8% | **7.0%** |

**What this shows:**
- **Cutting doesn't cost accuracy.** On long speech it slightly helps: each part gets Whisper's full 30-second window to itself.
- **No context between parts.** Passing the previous part's text to Whisper as a prompt was the fallback if accuracy dropped. It isn't needed.
- **Silent tails are gone.** Most eval clips end in about a second of silence, so the cut fires inside it. Nothing then remains to transcribe at release, where before the room noise would have been transcribed.

Runs: `v2-02-whole`, `v2-02-parts`, `v2-02-whole-en`, `v2-02-parts-en`.

## Sentence breaks: the one thing that gets worse

**Why.**
- Whisper ends every part it's given with a full stop and starts the next with a capital.
- Word error rate ignores punctuation, so `ovf-eval breaks` was added. It lines the output up with the reference and counts sentence breaks (. ? !) found in both, false (in the output only) and missed (in the reference only).

**Choosing the rule.** On the clips that get cut (6, 21-23, 29-37), Hinglish model:

| How a cut is joined | Breaks found | False | Missed |
|---|---|---|---|
| Whole clip (no cuts) | 40 | 5 | 7 |
| Keep every full stop | 39 | 27 | 6 |
| Remove it under 0.7 s of pause | 30 | 11 | 15 |
| **Remove it under 1.0 s** (chosen) | 24 | 5 | 21 |
| Remove it under 1.5 s | 20 | 5 | 25 |
| Always remove it | 20 | 4 | 25 |

**Why 1.0 s.**
- Pause length is a weak hint: no threshold gets near the whole clip.
- 1.0 s brings the jarring error, a full stop mid-sentence, back to the whole-clip level. The cost is run-on sentences: real sentence ends with neither the full stop nor the capital.
- The English model behaves the same way: whole 1 false / 1 missed, with 1.0 s 1 / 9 (clips 6, 21, 23, 35-37).

**Final runs, all clips:**

| Run | Found | False | Missed |
|---|---|---|---|
| Hinglish model, whole | 41 | 9 | 13 |
| Hinglish model, with cuts | 25 | 8 | 27 |
| English model, whole | 17 | 5 | 4 |
| English model, with cuts | 10 | 4 | 12 |

A better signal than pause length is v2 ticket 17.

## Speed: long dictations about three times faster

Release to text, Hinglish model, same session, audio played at speaking pace:

| Clips | Audio | Whole | With cuts |
|---|---|---|---|
| 29-37 (long) | 35-49 s | 6.24 s median | **2.07 s** |
| 21-23 | 14-22 s | 2.60 s | **1.31 s** |
| 1-5 (short) | 5-9 s | 2.02 s | **1.59 s** |

| Clip | Audio | Whole | With cuts | Parts, tail |
|---|---|---|---|---|
| 29 | 41.8 s | 5.73 s | 2.45 s | 5, 11.0 s |
| 31 | 49.4 s | 6.41 s | 2.40 s | 7, 10.5 s |
| 35 | 46.3 s | 6.86 s | 1.99 s | 6, 4.5 s |
| 37 | 46.4 s | 6.59 s | 1.90 s | 6, 5.2 s |

**What this shows:**
- **The wait now depends on the last stretch, not on the length.** The slowest long clips (29, 31) are the ones whose last 10-11 s had no pause.
- **Short clips got a little faster too.** The part is transcribed during the pause before release.

**Caveat: absolute times are inflated.**
- The runner's encoder is still 2-3 times slower than the app's log for the same model, as ticket 01 found.
- It is **not** macOS media analysis: clips 1-3 were re-timed with `mediaanalysisd` idle and still took 2.0 s against October's 0.82-0.85 s. The cause remains unknown.
- Both columns ran in the same session, so the comparison holds. The app's own times should be lower. The real-use acceptance comes from the app log: dictations of 20 s or more at about 1.6 s median, short ones no slower than 1.13 s.

Runs: `v2-02-speed-whole`, `v2-02-speed-realtime`.

**Not measured:** cloud speech (Deepgram) takes the same path but wasn't run.

## Reproducing

```sh
swift build -c release --product EvalRunner
M=~/Library/Application\ Support/open-voice-flow/models/oriserve-hinglish
EN=1,2,3,4,5,6,7,8,21,23,35,36,37,39,40,42,44
SPEED=1,2,3,4,5,21,22,23,29,30,31,32,33,34,35,36,37
.build/release/EvalRunner --name v2-02-whole --whole --model-folder "$M"
.build/release/EvalRunner --name v2-02-parts --model-folder "$M"
.build/release/EvalRunner --name v2-02-whole-en --whole --language english --ids $EN
.build/release/EvalRunner --name v2-02-parts-en --language english --ids $EN
.build/release/EvalRunner --name v2-02-speed-whole --whole --model-folder "$M" --ids $SPEED
.build/release/EvalRunner --name v2-02-speed-realtime --realtime --model-folder "$M" --ids $SPEED
# the rule's thresholds: --sentence-pause 0 / 0.7 / 1.0 / 1.5 / 99 on --ids 6,21,22,23,29,30,31,32,33,34,35,36,37
cd scripts/eval
uv run ovf-eval score v2-02-whole v2-02-parts
uv run ovf-eval breaks v2-02-whole v2-02-parts
```
