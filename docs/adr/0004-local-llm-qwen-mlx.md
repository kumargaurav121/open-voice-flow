# 4. Local LLM: Qwen3.5-2B on MLX-Swift

Status: Accepted · 2026-10-08

## Context
Need fast cleanup and reliable structured intent parsing, incl. Hindi. Small Llama models are weak at tool calling; Apple Foundation Models lacks Hindi; Ollama is a separate app and can't host STT models.

## Decision
Qwen3.5-2B 4-bit via MLX-Swift, in-process, downloaded from Hugging Face. Constrained/structured output for intents. 4B when RAM allows. Gemma 4, Ollama and cloud BYOK (e.g. Claude Haiku 4.5) as alternative providers. The LLM extracts names only; adapters resolve people deterministically.

## Consequences
No extra installs; offline after setup; ~1.5 GB download. Must validate parse reliability on Hinglish and step up model size if needed.
