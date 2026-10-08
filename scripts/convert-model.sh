#!/usr/bin/env bash
# Converts a pinned Hugging Face Whisper fine-tune to WhisperKit Core ML and installs it where the app
# looks (ADR 0010: pinned revision, data-only download, checksums, attribution).
#
#   scripts/convert-model.sh <repo> <revision> <install-name> <license> [work-dir]
#   scripts/convert-model.sh Oriserve/Whisper-Hindi2Hinglish-Apex f3214eed20b4 oriserve-hinglish Apache-2.0
#
# Needs ~10 GB free disk and Python 3.11 (via uv). Default tests must stay on: whisperkittools
# generates the encoder/decoder inside them.
set -euo pipefail

SOURCE_MODEL="$1"
SOURCE_REVISION="$2"
INSTALL_NAME="$3"
LICENSE="$4"
WORK="${5:-${TMPDIR:-/tmp}/ovf-conversion-$INSTALL_NAME}"
WHISPERKITTOOLS_REVISION="84f77a83c8f530022ae55fbb1a64b3351ef63c7a"
DEST="$HOME/Library/Application Support/open-voice-flow/models/$INSTALL_NAME"
PY="$WORK/whisperkittools/.venv/bin/python"

mkdir -p "$WORK"
if [[ ! -d "$WORK/whisperkittools" ]]; then
  git clone -q https://github.com/argmaxinc/whisperkittools.git "$WORK/whisperkittools"
  git -C "$WORK/whisperkittools" checkout -q "$WHISPERKITTOOLS_REVISION"
  uv venv -q --python 3.11 "$WORK/whisperkittools/.venv"
  uv pip install -q -p "$WORK/whisperkittools/.venv" -e "$WORK/whisperkittools"
fi

# Pinned revision, safetensors and config only (no pickle weights, no code), with checksums.
SOURCE_DIR="$WORK/source"
"$PY" - "$SOURCE_MODEL" "$SOURCE_REVISION" "$SOURCE_DIR" <<'PY'
import hashlib, sys
from pathlib import Path
from huggingface_hub import snapshot_download
repo, revision, dest = sys.argv[1:]
snapshot_download(repo, revision=revision, local_dir=dest,
                  allow_patterns=["*.safetensors", "*.safetensors.index.json", "*.json", "*.txt"])
if not list(Path(dest).glob("*.safetensors")):
    sys.exit(f"{repo}@{revision} has no safetensors weights; refusing (ADR 0010)")
with open(Path(dest) / "SHA256SUMS", "w") as sums:
    for f in sorted(Path(dest).glob("*")):
        if f.is_file() and f.name != "SHA256SUMS":
            sums.write(f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.name}\n")
PY

"$WORK/whisperkittools/.venv/bin/whisperkit-generate-model" --model-version "$SOURCE_DIR" --output-dir "$WORK/coreml"

converted="$(find "$WORK/coreml" -mindepth 1 -maxdepth 1 -type d | head -1)"
for model in MelSpectrogram AudioEncoder TextDecoder; do
  [[ -d "$converted/$model.mlmodelc" ]] || { echo "conversion produced no $model.mlmodelc" >&2; exit 1; }
done

rm -rf "$DEST" && mkdir -p "$DEST"
cp -R "$converted/"*.mlmodelc "$DEST/"
cp "$SOURCE_DIR/config.json" "$SOURCE_DIR/generation_config.json" "$DEST/" 2>/dev/null || true

# WhisperKit needs the model's own tokenizer.json, or it falls back to the stock one. Some repos ship
# only the slow-tokenizer files, so build it from the pinned source.
"$PY" - "$SOURCE_DIR" "$DEST" <<'PY'
import sys
from transformers import WhisperTokenizerFast
WhisperTokenizerFast.from_pretrained(sys.argv[1]).save_pretrained(sys.argv[2])
PY

cp "$SOURCE_DIR/SHA256SUMS" "$DEST/SOURCE-SHA256SUMS"
cat > "$DEST/ATTRIBUTION.md" <<ATTR
Core ML conversion of $SOURCE_MODEL at revision $SOURCE_REVISION
(https://huggingface.co/$SOURCE_MODEL), licensed $LICENSE by its authors.
Converted with argmaxinc/whisperkittools at $WHISPERKITTOOLS_REVISION.
Source file checksums: SOURCE-SHA256SUMS.
ATTR
echo "Installed to $DEST"
