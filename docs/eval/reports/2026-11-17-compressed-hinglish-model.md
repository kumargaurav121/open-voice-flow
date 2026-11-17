# The Hinglish model with a 6-bit encoder (2026-11-17)

**Why.**
- Same cause as the English model's change that day (`2026-11-17-compressed-english-model.md`): since
  mid-November, Core ML on our M1 Pro runs the Hinglish model's 1.27 GB float16 encoder on the CPU, 1.7-1.8 s
  per 30-second window. In October it ran on the Neural Engine at 0.62-0.70 s.
- A smaller encoder is taken by the Neural Engine again.

**What was built** (v2 ticket 05).
- The encoder's weights palettized to 6 bits: k-means, one 64-entry lookup table per weight tensor over
  2048 values (smaller ones, like biases and norms, stay float16), coremltools 9.0 `palettize_weights`.
  The encoder is 0.48 GB instead of 1.27 GB.
- The decoder and mel step aren't compressed. Their weights are the same as before. Rebuilt, their programs
  differ only in Core ML's build stamp and date.
- `generation_config.json` now has the alignment heads the model was converted with. The previous revision
  had the source's empty value. WhisperKit doesn't read this file.
- Uniform 6 bits, not the mixed-bit recipe the ticket named (Argmax's per-layer choice of bits). The
  uniform build met every bar first time, so mixed-bit wasn't needed.
- `scripts/convert-model.sh` builds it from pinned inputs: the source revision, whisperkittools by commit,
  coremltools 9.0. Rebuilt from scratch, every weight file and the encoder's program came out
  byte-identical to the pilot that was measured. The small metadata files (`coremldata.bin`,
  `metadata.json`) and the decoder and mel `model.mil` carry Core ML's build stamp and date, so a rebuild
  doesn't match the manifest's hashes for those. Built with Xcode 27.2 (`coremlcompiler` 3600.25.1).
- Published as revision `668ef2d23517d6f3da41622aff6b46089e466104` of
  `kumargaurav9013/whisper-hindi2hinglish-apex-coreml`. The full-size build stays at `f1cc87f9`.

**Measured** on all 44 clips, Hinglish mode, the app's pipeline (transcribing while you speak), no
dictionary, on the same Mac the same day:

| Hinglish model | Word errors (agnostic / strict) | en / hi / Hinglish (agnostic) | Median | p95 |
|---|---|---|---|---|
| Full-size encoder, on the CPU (`v2-02-parts`) | 13.6% / 19.2% | 11.8 / 9.3 / 15.2 | 2.09 s | 16.90 s |
| **6-bit encoder, as published** (`hinglish-6bit-final`) | **13.7% / 19.3%** | 11.8 / 7.0 / 15.5 | **0.85 s** | **6.41 s** |

- **Accuracy:** 0.1 points worse, inside the 0.5-point bar. The pilot run (`hinglish-6bit`) gave the same
  text on every clip.
- **Against ticket 01's baseline runs** (`app-oriserve-ane` for clips 1-28, `baseline-oriserve` for
  29-44). Those runs used the pipeline from before transcribing while you speak (ticket 02), so they mix
  two changes, and the table above is the controlled comparison.

  | Clips | Agnostic | Strict |
  |---|---|---|
  | 1-28 | 17.8% → 18.2% | 22.2% → 23.1% |
  | 29-44 | 12.3% → 11.9% | 18.6% → 17.8% |
- **Encoding**, timed back to back on the same 8 clips (`encode-full`, `encode-6bit`):
  - Full-size encoder: 1.69-1.80 s per window.
  - 6-bit encoder: 0.43-0.49 s per window, faster than October's 0.62-0.70 s on the Neural Engine.
- **Sentence breaks:** 25 found, 9 false, 26 missed, against 25 / 8 / 27.
- **First load** (the one-time Neural Engine compile, setup's "Preparing"): 311 s for the pilot, against
  967 s for the full-size model in October.

**What changes for users:**
- The Hinglish download is 0.84 GB instead of 1.6 GB, and all models together about 4.8 GB instead of 5.5 GB.
- Existing installs: setup reopens, downloads the new model into `oriserve-hinglish-6bit`, deletes the old
  folder, then prepares the new model once. Dictation waits until that's done, as with the English model's
  update (user's choice).
- **Why a new folder.** Updating `oriserve-hinglish` in place would keep its 0.35 GB of unchanged files
  (decoder weights, tokenizer) and fetch about 0.49 GB. A new folder downloads all 0.84 GB, but it never
  rewrites a compiled model that Core ML has already cached, and the old model stays untouched until the
  new one has fully downloaded and verified. This follows the English model's update (ticket 18).

Runs: `v2-02-parts`, `hinglish-6bit`, `hinglish-6bit-final`, `encode-full`, `encode-6bit`.
