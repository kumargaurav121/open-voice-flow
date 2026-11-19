# 13. Parakeet for English mode, in long parts

Status: Accepted · 2026-11-19 (v2 tickets 06, 07), below ticket 06's accuracy bar by the user's choice

## Context
- **English mode ran Whisper turbo,** cut at pauses (ADR 0012). It took about 1 s at release, and 1.9-2.5 s on
  long hands-free dictations: the parts transcribed while speaking fell behind.
- **NVIDIA Parakeet TDT 0.6B** reads a long stretch in one pass, with no 30-second window and no word-by-word
  decoding.
  - Ticket 06 tested it on the 17 English clips: within 0.5 points of turbo, and about 5 times faster at release.
    - Accuracy: whole clips 7.3% word errors, against turbo's 7.0% cut at pauses. With two scorer gaps fixed
      later (ticket 07), turbo was 6.5%: 0.8 points.
    - Speed at release: 0.08-0.29 s, against 0.78-1.27 s.
  - It needs the whole stretch:
    - Cut at every pause, it loses context: 8.1% errors.
    - Whole, it slows down on long recordings: 5.4-7.7 s for 10.8 minutes.
- **Parakeet v3** (25 languages, no Hindi) was worse on English than v2 (ticket 06).

## Decision
- **English mode runs Parakeet TDT 0.6B v2** through FluidAudio (Apache-2.0, pinned to 0.18.3, no traits),
  behind the language router. Hinglish mode is unchanged.
  - The Latin-script guard, the dictionary and cleanup still apply.
  - It loads at launch and warms up on a second of silence, as Whisper does.
- **Weights:** FluidInference's Core ML build, pinned and checksummed, as an exception to "convert ourselves"
  (ADR 0010, amendment for v2 ticket 07). NVIDIA is credited in the installed `ATTRIBUTION.md` and the README
  (CC-BY-4.0).
- **Long parts:** English on this Mac is cut only at a pause after 40 s of speech, or at the quietest moment
  after 60 s without one (`PauseCutter.Lengths.long`).
  - Most dictations are one part, transcribed whole at release.
  - Hinglish (Whisper) and cloud speech keep their parts at 2-25 s.
  - The user chose this after ticket 06's long-dictation result.
- **Numbers as digits:** Parakeet writes most numbers as words. The always-on rules cleanup now writes them the
  usual way, in every mode (`SpokenNumbers`):
  - 10 and up as digits.
  - Times, decimals, percentages and dates as digits: "11:30", "1.5 seconds", "5%", "1st of December".
    An hour and minutes are a time only next to a time word ("at eleven thirty", "eleven thirty tomorrow"),
    so "room two twelve" and "five ten minutes" stay words.
  - One to nine stay words otherwise.
  - Code editors still get the raw text.
- **Whisper turbo stays downloaded** but is no longer loaded or compiled during setup. Removing it is a later
  decision.

## Consequences
- **Accuracy** (eval through the app's pipeline: `docs/eval/reports/2026-11-18-parakeet-in-english-mode.md`):
  - 36 English clips (17 from eval set 2, 19 recorded for ticket 07): 6.8%, against Whisper's 6.1%. That is
    0.7 points, against ticket 06's bar of 0.5. The user chose to ship it.
  - The gap is the speaker's restarts. Parakeet writes them as said ("dropped from the from about"), and
    Whisper drops them: 11 words. Without them, Parakeet is at 5.9%. Ticket 19 removes them.
  - Long dictations: 4.6% and 4.7%, against Whisper's 4.9%.
  - The scorer was fixed on the way: "there's" now matches "there is", and "1.5" matches "one and a half".
- **Speed at release:**
  - 36 clips up to 46 s: median 0.19 s, slowest 0.53 s. Whisper: 0.79 s and 1.32 s.
  - 2.2 min: 0.11 s. 10.8 min: 0.18 s. Whisper took 0.89-0.90 s (1.93-2.48 s the day before).
- **Errors that differ from Whisper:**
  - Parakeet keeps the speaker's restarts ("We also we are also").
  - It writes spoken punctuation as words, which ticket 09 expects.
  - It hears some names differently: "Gujeep" for Gurjeet in one clip, "Warsaw" for Vercel, "Here Jun" for
    "Hey Arjun".
- **Setup:**
  - 0.46 GB more to download, about 5.2 GB in all.
  - Preparing is shorter: Parakeet compiles in about 30 s, and turbo is no longer compiled.
- **An English dictation shorter than 40 s is transcribed only at release.** Nothing is sent while speaking.
- **FluidAudio links into the app.** SwiftPM still downloads its prebuilt text-normalization binary when it
  resolves packages, but nothing links it: the app has none of its symbols.
