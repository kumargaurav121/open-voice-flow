# 12. Transcribe while you speak: cut at pauses

Status: Accepted · 2026-11-13 · Amended 2026-11-18 (v2 ticket 07)

## Context
- **All transcription started at release.** Long dictations waited the longest: by how long `fn` was held, the app log's median release-to-text was 2.65 s for 20-40 s and 4.26 s for 40 s or more, against 1.13 s under 5 s (docs/eval/reports/2026-11-13-eval-set-2-baseline.md).
- **Whisper pads every clip to a 30-second window,** so each transcription pays the encoder once, however short. Most of its time then goes to word-by-word decoding.
- **Three ways to start earlier were considered:**
  1. **WhisperKit's built-in streaming** (`AudioStreamTranscriber`). It re-transcribes the growing recording about every second and confirms segments by their timestamps. It needs timestamp tokens, which our Hinglish conversion isn't tested with, it owns the microphone (clashing with our recorder), and it keeps the Neural Engine busy throughout.
  2. **Overlapping fixed windows,** stitched by matching text. Word-stitching errors (dropped or doubled words) are hard to rule out.
  3. **Cutting at the speaker's own pauses** and transcribing each finished part in the background.

## Decision
Cut at pauses (option 3):
- **The pause cutter** (`PauseCutter`) watches the live audio.
  - **A pause** is 0.5 s or more that is within 10 dB of the room's noise and at least 20 dB below the loudest speech. That's stricter than the edge trimmer, so a speaker trailing off isn't a pause.
  - **A part** always holds speech and is at least 2 s long, counted from its first speech. Without a pause, it is cut at its quietest 100 ms once it reaches 25 s from its first speech.
  - **Nothing is cut** until something stands out from the room, so a silent or noisy room with nobody speaking is never sent off.
  - **The tail after the last cut is dropped when it's only silence**, as when the speaker pauses before letting go. The text is then ready at release.
- **`LiveTranscriber`** (inside the pipeline) takes the session's live audio. It cuts and trims it and transcribes each part in the background, then at release the tail.
  - **Joining:** it joins the texts with spaces. Where the pause at a cut was under 1 s, or there was none, it takes the cut to be mid-sentence: the full stop Whisper ends every part with goes, and the next word loses its capital. "I", acronyms and words capitalised elsewhere in the dictation (names) keep theirs.
  - **After the join:** English letters, the dictionary and cleanup run once on the whole text.
- **Every transcription goes through the same queue,** commands included, one at a time and in order. The speech engine isn't reentrant, even when a discarded part is still finishing.
- **If a part fails,** the rest of that dictation is skipped.
- **Scope:**
  - Commands stay whole: they are short and parsed as one.
  - Cloud speech uses the same path.
  - The language is fixed when the key goes down.
- **Esc**, during recording or after release but before pasting, discards the dictation, including parts already transcribed and work still queued.
- **The log line** gains the number of parts and the length of the tail.
- **No context is passed between parts** (no Whisper prompt): on the eval it isn't needed to hold accuracy (see the ticket 02 report).

## Consequences
- **Sentence breaks at cuts are a guess.**
  - Whisper ends every part with a full stop, and pause length is a weak hint of a real sentence end. On the eval's cut clips, the 1 s rule brings false breaks back to the whole-clip level (5), but misses 21 real breaks against 7. Those become run-on sentences without the capital.
  - The scores come from `ovf-eval breaks` (docs/eval/reports/2026-11-17-transcribe-while-you-speak.md). A better signal is a follow-up (v2 ticket 17).
- **Cloud speech now uploads while the key is held.** With Deepgram chosen, finished parts go to the cloud before release, so Esc no longer keeps all of the audio off the network.
- **Speed:** a dictation's wait at release depends on its last stretch, not its length. Short dictations without a pause are transcribed whole, as before.
- **Accuracy:** each part loses the context of the others. The eval bar is accuracy within 0.5 points of transcribing whole.
- **Groundwork:** this enables hands-free dictation (v2 ticket 04) and AI cleanup per part (ticket 16). It also gives the notch something to show while speaking, if a live preview is added later.

## Amendment (v2 ticket 07, 2026-11-18)
- **Part lengths now depend on the model.** The 2 s shortest part and the 25 s forced cut are Whisper's
  (`PauseCutter.Lengths.short`).
- **English mode on this Mac runs Parakeet** (ADR 0013), which is more accurate with a whole stretch of speech.
  Its parts are cut only at a pause after 40 s of speech, or at the quietest moment after 60 s without one
  (`.long`).
- **`LiveTranscriber` picks the lengths when a dictation starts,** from the language and the speech provider.

