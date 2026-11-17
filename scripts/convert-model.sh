#!/usr/bin/env bash
# Converts a pinned Hugging Face Whisper fine-tune to WhisperKit Core ML, compresses its audio encoder, and
# writes the model's files to <output-dir> (ADR 0010: pinned revision, data-only download, checksums,
# attribution). The app installs published models from their pinned manifests, never from here.
#
#   scripts/convert-model.sh <repo> <revision> <output-dir> <license> [work-dir]
#   scripts/convert-model.sh Oriserve/Whisper-Hindi2Hinglish-Apex f3214eed20b4e4d4144e739982d911f87b9cb223 \
#       ~/oriserve-hinglish-coreml Apache-2.0
#
# ENCODER_BITS (default 6) palettizes the audio encoder's weights: since November 2026 the Neural Engine
# on our M1 Pro refuses the 1.27 GB float16 encoder (it then runs on the CPU at ~2 s per window), and takes
# the 6-bit one (0.48 GB, ~0.45 s per window, eval within 0.1 points; v2 ticket 05). ENCODER_BITS=16 keeps
# the float16 encoder.
#
# Needs ~12 GB free disk and Python 3.11 (via uv). whisperkittools generates the encoder/decoder inside its
# tests, so they stay on, but run CPU-only (see below). Takes ~20 minutes on an M1 Pro.
set -euo pipefail

SOURCE_MODEL="$1"
SOURCE_REVISION="$2"
OUT="$3"
LICENSE="$4"
WORK="${5:-${TMPDIR:-/tmp}/ovf-conversion-$(basename "$OUT")}"
ENCODER_BITS="${ENCODER_BITS:-6}"
WHISPERKITTOOLS_REVISION="84f77a83c8f530022ae55fbb1a64b3351ef63c7a"
COREMLTOOLS_VERSION="9.0"

case "$ENCODER_BITS" in
  1|2|3|4|6|8|16) ;;
  *) echo "ENCODER_BITS must be 1, 2, 3, 4, 6 or 8 (palettized), or 16 (float16, uncompressed)" >&2; exit 1 ;;
esac
if [[ -e "$OUT" && -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
  echo "$OUT isn't empty; choose a new folder (this script never overwrites one)" >&2
  exit 1
fi
# Absolute paths: the conversion runs from inside whisperkittools (below).
mkdir -p "$WORK" "$(dirname "$OUT")"
WORK="$(cd "$WORK" && pwd)"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
PY="$WORK/whisperkittools/.venv/bin/python"

if [[ ! -d "$WORK/whisperkittools" ]]; then
  git clone -q https://github.com/argmaxinc/whisperkittools.git "$WORK/whisperkittools"
  git -C "$WORK/whisperkittools" checkout -q "$WHISPERKITTOOLS_REVISION"
  uv venv -q --python 3.11 "$WORK/whisperkittools/.venv"
  uv pip install -q -p "$WORK/whisperkittools/.venv" -e "$WORK/whisperkittools"
fi
# whisperkittools doesn't pin it exactly, and the palettized weights depend on it. Every run, in case the
# work folder came from an older run.
uv pip install -q -p "$WORK/whisperkittools/.venv" "coremltools==$COREMLTOOLS_VERSION"

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

# whisperkittools needs `alignment_heads` (cross-attention heads used for word timestamps) to build the
# decoder. Some fine-tunes ship it empty. For a turbo-architecture fine-tune (4 decoder layers) the heads
# are turbo's; anything else must be fixed by hand rather than guessed. Checksums above are of the
# unpatched source (the patch goes into a fresh copy each run); the patch is recorded in ATTRIBUTION.md.
CONVERT_DIR="$WORK/source-for-conversion"
rm -rf "$CONVERT_DIR" && cp -R "$SOURCE_DIR" "$CONVERT_DIR"
PATCHED="$("$PY" - "$CONVERT_DIR" <<'PY'
import json, sys
from pathlib import Path
src = Path(sys.argv[1])
gen_path, cfg = src / "generation_config.json", json.loads((src / "config.json").read_text())
gen = json.loads(gen_path.read_text())
if gen.get("alignment_heads"):
    print("")
elif cfg.get("decoder_layers") == 4 and cfg.get("d_model") == 1280:
    gen["alignment_heads"] = [[2, 4], [2, 11], [3, 3], [3, 6], [3, 11], [3, 14]]  # openai/whisper-large-v3-turbo
    gen_path.write_text(json.dumps(gen, indent=2))
    print("alignment_heads copied from openai/whisper-large-v3-turbo (empty in the source)")
else:
    sys.exit("generation_config.json has no alignment_heads and the architecture isn't turbo's; add them by hand")
PY
)"

# whisperkittools' built-in tests load each model on the Neural Engine and benchmark it. On an M1 that
# first-load compile can take an hour or wedge the system ANECompilerService, and it isn't needed to
# produce the model. Run the tests (and their PSNR accuracy check) on the CPU and skip the benchmarks.
# Keep each uncompiled .mlpackage too: the encoder is compressed from it below. It runs from whisperkittools'
# root because it imports that repo's `tests` package (from here, our `Tests/` would shadow it on a
# case-insensitive disk).
rm -rf "$WORK/coreml"
(cd "$WORK/whisperkittools" && "$PY" - "$CONVERT_DIR" "$WORK/coreml" <<'PY'
import sys
import coremltools as ct
from argmaxtools import test_utils
# Fail loudly if these internals move: silently falling back to the Neural Engine means an hour-long hang.
assert hasattr(test_utils, "TEST_COMPUTE_UNIT") and hasattr(test_utils, "TEST_SKIP_SPEED_TESTS") \
    and hasattr(test_utils, "_save_coreml_asset"), "whisperkittools test settings changed; update convert-model.sh"
test_utils.TEST_COMPUTE_UNIT = ct.ComputeUnit.CPU_ONLY
test_utils.TEST_SKIP_SPEED_TESTS = True
_save = test_utils._save_coreml_asset
def _keep(*args, **kwargs):
    kwargs["do_remove_mlpackage"] = False
    return _save(*args, **kwargs)
test_utils._save_coreml_asset = _keep
from scripts.generate_model import cli
sys.argv = ["whisperkit-generate-model", "--model-version", sys.argv[1], "--output-dir", sys.argv[2]]
cli()
PY
)

converted="$(find "$WORK/coreml" -mindepth 1 -maxdepth 1 -type d | head -1)"
for model in MelSpectrogram AudioEncoder TextDecoder; do
  [[ -d "$converted/$model.mlmodelc" ]] || { echo "conversion produced no $model.mlmodelc" >&2; exit 1; }
done

COMPRESSED=""
if [[ "$ENCODER_BITS" != 16 ]]; then
  [[ -d "$converted/AudioEncoder.mlpackage" ]] || { echo "conversion kept no AudioEncoder.mlpackage" >&2; exit 1; }
  # k-means palettization of each weight tensor over 2048 values (one lookup table per tensor; smaller ones,
  # like biases and norms, stay float16), with Core ML's own optimizer and its bundled 1-D k-means, so the
  # same coremltools gives the same weights. Per-tensor (not per-group) keeps it loadable on macOS 14.
  rm -rf "$WORK/palettized" "$WORK/compiled" && mkdir -p "$WORK/palettized" "$WORK/compiled"
  "$PY" - "$converted/AudioEncoder.mlpackage" "$WORK/palettized/AudioEncoder.mlpackage" "$ENCODER_BITS" \
    "$COREMLTOOLS_VERSION" <<'PY'
import sys
import coremltools as ct
import coremltools.optimize as cto
source, dest, nbits, version = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
assert ct.__version__ == version, f"coremltools {ct.__version__}, expected {version}"
model = ct.models.MLModel(source, skip_model_load=True)
config = cto.coreml.OptimizationConfig(
    global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=nbits, granularity="per_tensor"))
cto.coreml.palettize_weights(model, config).save(dest)
PY
  rm -rf "$converted/AudioEncoder.mlmodelc"
  xcrun coremlcompiler compile "$WORK/palettized/AudioEncoder.mlpackage" "$WORK/compiled" >/dev/null
  mv "$WORK/compiled/AudioEncoder.mlmodelc" "$converted/AudioEncoder.mlmodelc"
  COMPRESSED="AudioEncoder weights palettized to $ENCODER_BITS bits (k-means, one table per tensor) with coremltools $COREMLTOOLS_VERSION palettize_weights."
fi

mkdir -p "$OUT"
cp -R "$converted/"*.mlmodelc "$OUT/"
# The generation config the model was converted with (patched copy); everything else from the pristine source.
cp "$SOURCE_DIR/config.json" "$CONVERT_DIR/generation_config.json" "$OUT/"

# WhisperKit needs the model's own tokenizer.json, or it falls back to the stock one. Some repos ship
# only the slow-tokenizer files, so build it from the pinned source.
"$PY" - "$SOURCE_DIR" "$OUT" <<'PY'
import sys
from transformers import WhisperTokenizerFast
WhisperTokenizerFast.from_pretrained(sys.argv[1]).save_pretrained(sys.argv[2])
PY

cp "$SOURCE_DIR/SHA256SUMS" "$OUT/SOURCE-SHA256SUMS"
cat > "$OUT/ATTRIBUTION.md" <<ATTR
Core ML conversion of $SOURCE_MODEL at revision $SOURCE_REVISION
(https://huggingface.co/$SOURCE_MODEL), licensed $LICENSE by its authors.
Converted with argmaxinc/whisperkittools at $WHISPERKITTOOLS_REVISION.
Source file checksums: SOURCE-SHA256SUMS (before any patch).
${PATCHED:+Patched before conversion: $PATCHED.}
${COMPRESSED:+Compressed: $COMPRESSED}
ATTR
echo "Wrote $OUT. To publish (ADR 0010), add the license's full text as LICENSE and a model card (README.md)"
echo "that discloses the patch and the compression, then SHA256SUMS of every file."
