# Parakeet on the app's own recordings (2026-11-27)

**The question** (v2 ticket 20). Ticket 07 put Parakeet in English mode on eval clips recorded as Voice Memos.
Does it hear audio the app recorded from the mic (`MicRecorder`: 16 kHz mono, trimmed) as well as Whisper turbo?
On 2026-11-20 two of the first three English dictations came out misheard ("review of 33", "from 12:12 value
percent to invoice counts"), with no audio kept.

**Short answer: yes.** Neither model misheard a word in 8 recordings, including the two sentences misheard on
Nov 20. The one difference is a restart the speaker made, which Parakeet writes as said (ADR 0022 leaves "a
fragment with a vowel"). Parakeet isn't clearly worse, so English mode keeps it with no decision needed.

**What was tested.**
- **Recordings:** the user turned on Keep audio recordings and read 8 short messages, one per dictation, in
  English mode with AI Cleanup off, in TextEdit (2026-11-27, one session). The script's first two lines are the
  Nov 20 sentences.
- **Mic:** not named yet. The default input right after the session was the MacBook Pro's built-in mic, but
  that doesn't show what the app recorded from.
- **The kept WAVs** (16 kHz mono, 2.4-8.5 s, 43 s in all) were copied to a scratch clips folder and run through
  `EvalRunner --clips` at speaking pace (`--realtime`), with the app's text pipeline, no dictionary:
  - **Parakeet v2** (`--stt parakeet-v2`, the installed model, long parts): run `t20-v2`.
  - **Whisper turbo** (as installed, cut at pauses): run `t20-turbo`.
- **References:** the script, changed where the speaker said something else (both models agree on it):
  - clip 3 "I have" for "I've";
  - clip 4 "stand-up" for "standup" (a spelling only, the same for both);
  - clip 5 "faster than the older laptops" for "faster on older laptops". The speaker restarted here: Parakeet
    wrote "than the old wa older laptops". Nobody listened to the clip, so this reference is Whisper's reading,
    and the restart is scored both ways below.
- **Scored** with `ovf_eval.score` on the scratch folder. Scratch copies deleted afterwards.

## Accuracy (99 words)

| | Parakeet | Whisper turbo |
|---|---|---|
| Words misheard | 0 | 0 |
| Restart (clip 5), counted as meant | 2 ("old wa" kept) | 0 |
| Restart (clip 5), counted as said | 0 | 2 ("old wa" dropped) |
| Scorer artefact: "%" loses "percent" (clips 2 and 5) | 2 | 2 |
| **Word error rate, restart as meant** | **4.0%** (4 words) | **2.0%** (2 words) |

- **The Nov 20 sentences came out right**, in the app (the text the user pasted) and on replay:
  "Can we move the design review to 3:30 tomorrow?" and "The cloud bill went up by 12%, and the invoice comes
  on Friday."
- **The replay matches the app:** the words the app pasted are the words of `t20-v2` on all 8 clips. Only
  punctuation differs on clips 6 and 7.
- **The scorer artefact:** `normalize` turns "12%" into "twelve" without "percent", so a reference saying
  "percent" costs every model a word. In the main eval only clip 49 says "percent".

## Time from release to text

| | Median | Slowest |
|---|---|---|
| Parakeet | 0.14 s | 0.18 s |
| Whisper turbo | 0.85 s | 1.66 s |

## What this doesn't show
- **One session, one mic, read speech, 8 short clips.** Nov 20's mic input changed nine times that morning;
  that wasn't reproduced, so this clears the app's recording path but doesn't explain that morning.
- **No dictation was cut while spoken** (every clip under 9 s), so nothing here for sentence breaks at cuts
  (ADR 0021).
