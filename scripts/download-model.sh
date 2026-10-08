#!/usr/bin/env bash
# Downloads a ready-to-run (MLX) model from Hugging Face into the app's models folder, following ADR 0010:
# pinned full commit SHA, data files only (safetensors, json, txt, and jinja chat templates, which are
# rendered by the tokenizer, not executed), checksums, attribution. Installs into an empty folder.
#
#   scripts/download-model.sh <repo> <revision> <install-name> <license>
#   scripts/download-model.sh mlx-community/Qwen3-1.7B-4bit 3b1b1768f8f8cf8351c712464f906e86c2b8269e qwen3-1.7b-4bit Apache-2.0
set -euo pipefail

REPO="$1"
REVISION="$2"
INSTALL_NAME="$3"
LICENSE="$4"
DEST="$HOME/Library/Application Support/open-voice-flow/models/$INSTALL_NAME"
[[ "$REVISION" =~ ^[0-9a-f]{40}$ ]] || { echo "revision must be a full 40-character commit SHA" >&2; exit 1; }
rm -rf "$DEST"  # no leftovers from another revision get hashed or loaded

uv run --quiet --with "huggingface_hub>=0.25" python - "$REPO" "$REVISION" "$DEST" <<'PY'
import hashlib, sys
from pathlib import Path
from huggingface_hub import snapshot_download
repo, revision, dest = sys.argv[1:]
snapshot_download(repo, revision=revision, local_dir=dest,
                  allow_patterns=["*.safetensors", "*.json", "*.txt", "*.jinja"])
dest = Path(dest)
if not list(dest.glob("*.safetensors")):
    sys.exit(f"{repo}@{revision} has no safetensors weights; refusing (ADR 0010)")
with open(dest / "SOURCE-SHA256SUMS", "w") as sums:
    for f in sorted(dest.glob("*")):
        if f.is_file() and f.name not in ("SOURCE-SHA256SUMS", "ATTRIBUTION.md"):
            sums.write(f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.name}\n")
PY

rm -rf "$DEST/.cache"
cat > "$DEST/ATTRIBUTION.md" <<ATTR
$REPO at revision $REVISION (https://huggingface.co/$REPO), licensed $LICENSE by its authors.
Downloaded unmodified; file checksums in SOURCE-SHA256SUMS.
ATTR
echo "Installed to $DEST"
