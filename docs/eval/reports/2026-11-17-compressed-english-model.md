# English mode on Argmax's compressed Whisper turbo (2026-11-17)

**Why.**
- Since mid-November, Core ML on our M1 Pro plans every operation of both 1.2 GB encoders on the CPU, though the app asks for the Neural Engine. In the app log, the Hinglish model's encoder took 0.62-0.70 s per 30-second window until 5 November and 1.7-2+ s since.
- The Neural Engine still takes the decoders, the mel step and smaller encoders. The model files are unchanged since 9 October and macOS wasn't updated. Its logs need admin rights, so the cause is unknown.
- Core ML plans Argmax's compressed (mixed-bit) turbo entirely on the Neural Engine: 16,235 operations, none on the CPU. That's the `openai_whisper-large-v3-v20240930_turbo_632MB` folder of the same repo, at the same pinned commit `0f63a780`.

**Measured** on the 17 English clips, English mode settings, one session, whole clips:

| English model | Word errors | Median time | p95 |
|---|---|---|---|
| Full-size turbo (installed until now, on the CPU) | 7.8% | 2.01 s | 5.18 s |
| Compressed encoder with the full-size decoder (trial only) | 8.3% | 0.90 s | 2.97 s |
| **Compressed turbo, as Argmax ships it** (chosen) | **8.6%** | **0.92 s** | 3.09 s |

- **Encoding:** 0.57 s per window, back to October's level.
- **Sentence breaks:** 17 found, 4 false, 4 missed, against 17 / 5 / 4 for the full-size model.
- **Where the words differ** (about 5 more errors in 603 words, both ways):
  - Worse: "Vercel" → "versel" (the dictionary fixes it); "now" → "not"; "team" → "too"; a dropped "seconds".
  - Better: spoken punctuation in clip 42, 3 errors → 0.

**Decision (user):** take Argmax's compressed model as-is. It's 0.8 points over the 0.5-point bar we use for changes that affect accuracy, accepted for twice the speed. Mixing the compressed encoder with the full-size decoder was 2 words better, but it's an untested combination with more setup code.

**What changes for users:**
- The English model download is 0.65 GB instead of 1.6 GB, and all models together about 5.5 GB.
- Existing installs download it through setup, which reopens when a pinned model is missing, then prepare it once (the first Neural Engine compile took 5 minutes here). The replaced folder is then deleted.

Runs: `enc-installed`, `enc-compressed`, `enc-632`.
