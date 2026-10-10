# 4. Local LLM on MLX-Swift (Qwen3; see amendment)

Status: Accepted · 2026-10-08 · Amended 2026-10-09 (ticket 05)

## Context
Need fast cleanup and reliable structured intent parsing, incl. Hindi. Small Llama models are weak at tool calling; Apple Foundation Models lacks Hindi; Ollama is a separate app and can't host STT models.

## Decision
A local Qwen3 model via MLX-Swift, in-process, downloaded from Hugging Face. *Originally planned as Qwen3.5-2B for cleanup and intents; ticket 05 replaced that with an opt-in Fast (Qwen3-1.7B) / Thorough (Qwen3-4B-Instruct) choice, see the amendment.* Constrained/structured output for intents (ticket 11). Ollama and cloud BYOK as alternative providers. The LLM extracts names only; adapters resolve people deterministically.

## Consequences
No extra installs; offline after setup; ~1.5 GB download. Must validate parse reliability on Hinglish and step up model size if needed.

## Amendment (ticket 05)
Cleanup is a rules pass on every dictation plus an **opt-in** AI pass, chosen in the menu: Off (default),
Fast = `mlx-community/Qwen3-1.7B-4bit` @ `3b1b1768f8f8cf8351c712464f906e86c2b8269e`, Thorough = `mlx-community/Qwen3-4B-Instruct-2507-4bit`
@ `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b` (both Apache-2.0, safetensors, installed by `scripts/download-model.sh`). Qwen3.5-2B was not
used: its 1.7 GB file carries vision weights and it was no better suited than Qwen3. On unseen spontaneous
Hinglish, 1.7B mostly left fillers in place and sometimes dropped meaning-bearing words; 4B cleaned well.
An output guard (deletions limited to fillers and repeats, no new words, English letters) makes either safe.
Cost: ~0.6 s (Fast) / ~1.3 s (Thorough) per dictation, so it is off by default. mlx-swift-lm's
MLXHuggingFace needs swift-transformers 1.3+, which conflicts with WhisperKit's 1.1.x pin, so the LLM
package adapts swift-transformers 1.1 tokenizers itself. MLX's Metal kernels build under SwiftPM once
Xcode's Metal Toolchain component is installed (`xcodebuild -downloadComponent MetalToolchain`).

## Amendment (ticket 11)
Commands are parsed **rules first**: direct phrasings ("Message Gurjeet saying …", "Gurjeet ko message karo
ki …") by pattern, instantly and exactly. Only other phrasings go to the LLM, always the local Qwen3-1.7B
(never the cloud), as JSON validated against the one known intent; an invalid reply, another app, or a
recipient the speaker didn't name is "unknown". The model only extracts; nothing is executed until the
adapter (ticket 12). See docs/eval/reports/2026-10-10-commands.md.

