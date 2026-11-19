#!/usr/bin/env python3
"""Generates Sources/ModelStore/BuiltInModels.swift: every model onboarding downloads, pinned to a full
commit SHA, with each file's size and SHA-256 (ADR 0010). The app refuses any byte that doesn't match.

    python3 scripts/make-manifests.py

LFS files take their SHA-256 from the Hugging Face API; small (non-LFS) files are downloaded at the pinned
revision and hashed here. Only data files are listed: weights, configs, tokenizers, compiled Core ML
models (ADR 0010). Re-run after bumping a pin, then re-run the eval.
"""
import hashlib
import json
import sys
import urllib.parse
import urllib.request
from fnmatch import fnmatch
from pathlib import Path

MLX = ["*.safetensors", "*.json", "*.txt", "*.jinja"]
COREML = ["*.mlmodelc/*", "config.json", "generation_config.json"]
PROVENANCE = ["ATTRIBUTION.md", "SOURCE-SHA256SUMS", "LICENSE"]

# id, folder, repo, revision, subfolder in the repo, allow-list, license, credit (when the publisher converted
# someone else's model: ATTRIBUTION.md names its authors)
MODELS = [
    # Argmax's compressed (mixed-bit) turbo: the full-size encoder (1.2 GB) is no longer accepted by the Neural
    # Engine on our M1 Pro and runs on the CPU at about 2 s a dictation; this one runs there (v2 ticket 18).
    ("whisper-turbo", "whisper-turbo-632mb", "argmaxinc/whisperkit-coreml",
     "0f63a7800b00dd0226abd051b906c246e1907482", "openai_whisper-large-v3-v20240930_turbo_632MB", COREML, "MIT", ""),
    # Turbo's tokenizer, from OpenAI's own repo (the files WhisperKit would fetch itself).
    ("whisper-turbo-tokenizer", "whisper-turbo-tokenizer", "openai/whisper-large-v3",
     "06f233fe06e710322aca913c1bc4249a0d71fce1", "", ["tokenizer.json", "tokenizer_config.json", "config.json"],
     "Apache-2.0", ""),
    # Our Core ML conversion (scripts/convert-model.sh) of Oriserve/Whisper-Hindi2Hinglish-Apex @ f3214eed, its
    # encoder palettized to 6 bits so the Neural Engine takes it, as with turbo above (v2 ticket 05).
    ("hinglish", "oriserve-hinglish-6bit", "kumargaurav9013/whisper-hindi2hinglish-apex-coreml",
     "668ef2d23517d6f3da41622aff6b46089e466104", "", ["*.mlmodelc/*", "*.json", "*.txt"] + PROVENANCE,
     "Apache-2.0", ""),
    # English mode's model: NVIDIA's Parakeet TDT 0.6B v2, in FluidInference's Core ML build (the FluidAudio
    # maintainers'; ADR 0013). Only the four models FluidAudio loads for v2 and the vocabulary: the repo holds
    # seven older variants too.
    ("parakeet", "parakeet-tdt-0.6b-v2", "FluidInference/parakeet-tdt-0.6b-v2-coreml",
     "ee09c569f73759e6d44c9bd16766f477b2b36d39", "",
     ["Preprocessor.mlmodelc/*", "Encoder.mlmodelc/*", "Decoder.mlmodelc/*", "JointDecision.mlmodelc/*",
      "parakeet_vocab.json"], "CC-BY-4.0",
     "Parakeet TDT 0.6B v2 by NVIDIA (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), licensed CC-BY-4.0 "
     "(https://creativecommons.org/licenses/by/4.0/). Converted to Core ML by FluidInference."),
    ("cleanup-fast", "qwen3-1.7b-4bit", "mlx-community/Qwen3-1.7B-4bit",
     "3b1b1768f8f8cf8351c712464f906e86c2b8269e", "", MLX, "Apache-2.0", ""),
    ("cleanup-thorough", "qwen3-4b-instruct-2507-4bit", "mlx-community/Qwen3-4B-Instruct-2507-4bit",
     "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b", "", MLX, "Apache-2.0", ""),
]


def get(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def list_files(repo, revision, subfolder, allow):
    """(path within the model, size, sha256) for every allowed file at the pinned revision."""
    tree_url = f"https://huggingface.co/api/models/{repo}/tree/{revision}/{subfolder}?recursive=true"
    files = []
    for entry in json.loads(get(tree_url)):
        if entry["type"] != "file":
            continue
        path = entry["path"][len(subfolder) + 1:] if subfolder else entry["path"]
        if not any(fnmatch(path, pattern) for pattern in allow):
            continue
        if entry.get("lfs"):
            sha, size = entry["lfs"]["oid"], entry["lfs"]["size"]
        else:
            data = get(f"https://huggingface.co/{repo}/resolve/{revision}/{urllib.parse.quote(entry['path'])}")
            sha, size = hashlib.sha256(data).hexdigest(), len(data)
        files.append((path, size, sha))
    if not files:
        sys.exit(f"{repo}@{revision}: no allowed files")
    return sorted(files)


def swift_name(model_id):
    return "".join(part.capitalize() if i else part for i, part in enumerate(model_id.split("-")))


def swift(model_id, folder, repo, revision, subfolder, license, credit, files):
    rows = "\n".join(f'            .init(path: "{p}", size: {s}, sha256: "{h}"),' for p, s, h in files)
    subfolder_arg = f'\n        subfolder: "{subfolder}",' if subfolder else ""
    credit_arg = f'\n        credit: "{credit}",' if credit else ""
    return f'''    /// {repo}{f" ({subfolder})" if subfolder else ""}, {license}
    public static let {swift_name(model_id)} = ModelManifest(
        id: "{model_id}", folderName: "{folder}", repo: "{repo}",
        revision: "{revision}",{subfolder_arg}
        license: "{license}",{credit_arg}
        files: [
{rows}
        ]
    )'''


def main():
    blocks = []
    for model_id, folder, repo, revision, subfolder, allow, license, credit in MODELS:
        assert len(revision) == 40, f"{repo}: revision must be a full commit SHA"
        files = list_files(repo, revision, subfolder, allow)
        print(f"{model_id}: {len(files)} files, {sum(f[1] for f in files) / 1e9:.2f} GB", file=sys.stderr)
        blocks.append(swift(model_id, folder, repo, revision, subfolder, license, credit, files))
    names = ", ".join(swift_name(m[0]) for m in MODELS)
    out = Path(__file__).resolve().parent.parent / "Sources/ModelStore/BuiltInModels.swift"
    out.write_text(
        "// Generated by scripts/make-manifests.py. Do not edit by hand.\n\n"
        "public enum BuiltInModels {\n"
        "    /// Everything onboarding installs.\n"
        f"    public static let all = [{names}]\n\n"
        + "\n\n".join(blocks) + "\n}\n"
    )
    print(f"wrote {out}", file=sys.stderr)


main()
