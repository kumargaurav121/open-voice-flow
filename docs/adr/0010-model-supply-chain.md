# 10. Model supply chain: only verifiable, pinned, data-only downloads

Status: Accepted · 2026-10-08

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
