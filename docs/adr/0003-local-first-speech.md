# 3. Local-first STT with a Hinglish Whisper model

Status: Accepted · 2026-10-08 · Amended 2026-10-08 (ticket 03)

## Context
Accuracy is the top priority across English, Hindi and Hinglish. Stock Whisper is ~30% WER on Hindi/Hinglish; Apple SpeechAnalyzer has no on-device Hindi; Wispr Flow is cloud-only.

## Decision
Default STT is `Trelis/whisper-hinglish-preview` (Apache 2.0; ~13.7% WER Hinglish, ~6.9% English), converted once by this project to WhisperKit Core ML and published on Hugging Face. Whisper large-v3-turbo is the interim fallback. Parakeet (English-only) and cloud BYOK are optional providers. Batch transcription after key release (no streaming in v1). Output in Latin script by default, Devanagari optional.

## Consequences
One model covers all three languages without language detection. ~1.6 GB download. We own a conversion + hosting step. Script normalisation needs the LLM cleanup pass.

## Amendment (ticket 03)
Trelis matched its accuracy in the app but is large-v3: it never finished compiling for the Neural
Engine on an M1 Pro (80+ min) and took 7.9 s per clip on the GPU, against a 1.5 s target. Replaced by
a **picker**: Hinglish mode runs `Oriserve/Whisper-Hindi2Hinglish-Apex` (turbo-sized, writes Roman
Hinglish, 17.5% agnostic / 22.0% strict WER, no translations) with `<|en|>` forced; English mode runs
stock turbo (7.0% English WER). Details: addendum in docs/eval/reports/2026-10-08-bakeoff.md.
