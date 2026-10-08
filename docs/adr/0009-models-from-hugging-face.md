# 9. Download models from Hugging Face at onboarding

Status: Accepted · 2026-10-08

## Context
~3 GB of models. Ollama hosts no STT models and requires a separate app; MLX can't load Ollama's GGUF files.

## Decision
Download STT and LLM models from Hugging Face during onboarding (free, no account for public repos), resumable and checksum-verified, into Application Support. Not bundled in the app.

## Consequences
Small app binary; models update independently. Subject to Hugging Face's generous anonymous rate limits.
