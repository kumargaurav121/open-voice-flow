# 10. Model supply chain: only verifiable, pinned, data-only downloads

Status: Accepted · 2026-10-08 · Amended 2026-10-09 (ticket 05)

## Context
The app and its tooling download multi-GB models from Hugging Face and convert them with third-party
tools. A model file can be an attack vector: PyTorch pickle checkpoints (`.bin`, `.pt`) execute code
when loaded, `trust_remote_code` runs repo-supplied Python, prebuilt Core ML bundles from unknown
publishers can't be checked against their claimed source, and a repo can change after we evaluated it.

## Decision
- **Data-only formats.** Load weights only from `.safetensors` (`use_safetensors=True`), never with
  `trust_remote_code`. Download with allow-lists (`*.safetensors`, `*.json`, `*.txt`).
- **Pin everything.** Every model is referenced by repo **and commit revision**; tools (whisperkittools)
  by git commit. Bumping a pin is a deliberate change that re-runs the eval.
- **Convert ourselves.** Core ML models shipped to users are converted by us from the pinned original
  weights with Argmax's official tooling. Third-party prebuilt Core ML bundles are not used, even when
  they exist (e.g. VocaHQ's Hinglish build).
- **Vet the publisher.** Before first use: license, publisher, download count, model card, no code files.
- **Record provenance.** Installed models carry `ATTRIBUTION.md` (source repo + revision + license) and
  `SOURCE-SHA256SUMS` of the source files.
- **Exception:** stock Whisper turbo comes from Argmax's own `argmaxinc/whisperkit-coreml` repo, the
  WhisperKit maintainers' official distribution.

## Consequences
Slower to try new models (a conversion per candidate), but every shipped model is traceable to pinned,
code-free source weights. Onboarding downloads (ticket 07) must verify checksums before installing, and
our own published models must ship a checksum manifest.

## Amendment (ticket 05)
- **Pins are full 40-character commit SHAs** (`download-model.sh` refuses anything else).
- **`*.jinja`** joins the allow-list: chat templates are rendered by the tokenizer, not executed.
- **MLX LLM weights come prebuilt from `mlx-community`**, a deliberate exception to "convert ourselves":
  it is the MLX project's own conversion org (hundreds of thousands of downloads), the files are plain
  safetensors quantised from the named upstream model, and re-quantising them ourselves would add no
  verification. They are still pinned, allow-listed and checksummed. Core ML models are still converted
  by us.
- `SOURCE-SHA256SUMS` records what was downloaded; verifying downloads against a published manifest is
  onboarding's job (ticket 07).

## Amendment (ticket 07)
- **The manifest is built into the app.** `scripts/make-manifests.py` generates
  `Sources/ModelStore/BuiltInModels.swift`: every model's repo, full commit SHA, and each file's size and
  SHA-256 (LFS hashes from the Hugging Face API, small files hashed at the pinned revision). Onboarding
  verifies every file before moving it into place; a mismatch deletes that model's whole download and
  installs nothing from it. Each installed model gets `ATTRIBUTION.md` and `SOURCE-SHA256SUMS` (written by
  the app unless the model ships its own).
- **Allow-list for Core ML models:** compiled `*.mlmodelc/*` contents (`coremldata.bin`, `model.mil`,
  `model.mlmodel`, `metadata.json`, `weights/weight.bin`) are model data, not code, and are allowed for
  Core ML repos only: Argmax's turbo (the existing exception) and our own conversion.
- **Turbo's tokenizer** comes from `openai/whisper-large-v3` (OpenAI's official repo, Apache-2.0), pinned at
  `06f233fe06e710322aca913c1bc4249a0d71fce1`, tokenizer JSON files only; the same files WhisperKit used to
  fetch itself, now pinned and checksummed.
- **Our published model:** `kumargaurav9013/whisper-hindi2hinglish-apex-coreml` at
  `f1cc87f9820d55650413305d00218343cb1d0da6`, with `ATTRIBUTION.md`, `LICENSE` (Apache-2.0),
  `SOURCE-SHA256SUMS`, a model card disclosing the alignment-heads patch, and `SHA256SUMS` of every file.
