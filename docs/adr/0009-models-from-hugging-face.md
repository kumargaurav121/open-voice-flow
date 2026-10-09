# 9. Download models from Hugging Face at onboarding

Status: Accepted · 2026-10-08 · Amended 2026-10-09 (ticket 07)

## Context
~6.5 GB of models (two speech models, two cleanup models). Ollama hosts no STT models and requires a separate app; MLX can't load Ollama's GGUF files.

## Decision
Download STT and LLM models from Hugging Face during onboarding (free, no account for public repos), resumable and checksum-verified, into Application Support. Not bundled in the app.

## Consequences
Small app binary; models update independently. Subject to Hugging Face's generous anonymous rate limits.

## Amendment (ticket 07)
Onboarding downloads everything (user decision), including our converted Hinglish model, which is
published under Apache-2.0 at `kumargaurav9013/whisper-hindi2hinglish-apex-coreml` (a free public repo:
no hosting or download fees). WhisperKit no longer downloads turbo itself; existing hub-cached copies are
not reused, so they download once more into the manifest's folder.
