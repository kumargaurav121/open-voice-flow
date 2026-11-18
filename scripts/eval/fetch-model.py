#!/usr/bin/env python3
"""Downloads a Hugging Face model at a pinned commit into a new folder, for evaluating a model before it
joins the built-in manifests (ADR 0010). Data files only (compiled Core ML, safetensors, json, txt, md);
each is verified, LFS files against the SHA-256 the commit records and small files against their git blob
SHA-1. A mismatch deletes the folder. Writes ATTRIBUTION.md and SOURCE-SHA256SUMS, like the app's installs.

    fetch-model.py <repo> <40-char revision> <dest> <pattern> [<pattern> ...]
    python3 -I scripts/eval/fetch-model.py FluidInference/parakeet-tdt-0.6b-v2-coreml \\
        ee09c569f73759e6d44c9bd16766f477b2b36d39 ~/parakeet-v2 'Preprocessor.mlmodelc/*' 'Encoder.mlmodelc/*' \\
        'Decoder.mlmodelc/*' 'JointDecision.mlmodelc/*' parakeet_vocab.json
"""
import hashlib
import json
import re
import shutil
import sys
import urllib.parse
import urllib.request
from fnmatch import fnmatch
from pathlib import Path

DATA_SUFFIXES = (".safetensors", ".json", ".txt", ".md")


def get(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def is_data(path):
    return ".mlmodelc/" in path or path.endswith(DATA_SUFFIXES)


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    repo, revision, dest, *allow = sys.argv[1:]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        sys.exit("revision must be a full 40-character commit SHA")
    dest = Path(dest)
    if dest.exists():
        sys.exit(f"{dest} exists; choose a new folder")
    tree = json.loads(get(f"https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true"))
    files = sorted((e for e in tree if e["type"] == "file" and any(fnmatch(e["path"], p) for p in allow)),
                   key=lambda e: e["path"])
    if not files:
        sys.exit("no files match")
    if code := [e["path"] for e in files if not is_data(e["path"])]:
        sys.exit(f"not data files, refusing (ADR 0010): {', '.join(code)}")
    sums = []
    for entry in files:
        path = entry["path"]
        data = get(f"https://huggingface.co/{repo}/resolve/{revision}/{urllib.parse.quote(path)}")
        sha256 = hashlib.sha256(data).hexdigest()
        if entry.get("lfs"):
            ok = sha256 == entry["lfs"]["oid"] and len(data) == entry["lfs"]["size"]
        else:
            ok = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest() == entry["oid"]
        if not ok:
            shutil.rmtree(dest, ignore_errors=True)
            sys.exit(f"{path}: checksum mismatch; deleted {dest}")
        out = dest / path
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        sums.append(f"{sha256}  {path}")
        print(f"ok {len(data) / 1e6:8.1f} MB  {path}", file=sys.stderr)
    (dest / "SOURCE-SHA256SUMS").write_text("\n".join(sums) + "\n")
    (dest / "ATTRIBUTION.md").write_text(
        f"{repo} at revision {revision} (https://huggingface.co/{repo}), fetched for evaluation.\n"
        "Downloaded unmodified; file checksums in SOURCE-SHA256SUMS.\n")
    print(f"{repo}@{revision}: {len(files)} files verified into {dest}", file=sys.stderr)


main()
