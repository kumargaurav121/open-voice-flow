#!/usr/bin/env python3
"""Split an eval reading into per-item clips.

Usage:
  scripts/eval/split.py docs/eval/raw/reading-YYYYMMDD.m4a --ids 1-28        # auto-detect pauses
  scripts/eval/split.py docs/eval/raw/reading-YYYYMMDD.m4a --ids 1-28 --segments docs/eval/segments/reading-YYYYMMDD.json
  # items 29-44 (reading-script-long.md): pauses inside an item go up to ~2 s, so only longer ones separate items
  scripts/eval/split.py docs/eval/raw/long/reading-long-20261113.m4a --ids 29-44 --min-silence 2.8 --pad 0.4 \
      --segments docs/eval/segments/reading-long-20261113.json

--ids names the reference items the recording holds, in order (default: every item). Without
--segments, pauses are detected with ffmpeg silencedetect and the result is written to
docs/eval/segments/<name>.json for review. Clips are only cut when the segment count matches the
items; otherwise fix the segments file by hand (e.g. split two items that were read without a pause)
and re-run with it.

Writes docs/eval/clips/NN.wav (16 kHz mono) and updates those items' rows in docs/eval/clips/manifest.json,
keeping the rows of items cut from other recordings.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

EVAL = Path(__file__).resolve().parents[2] / "docs" / "eval"
PAD = 1.0  # seconds of context kept around each segment, capped at the gap midpoint


def duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    return float(out)


def detect_segments(path, noise_db, min_silence):
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path),
         "-af", f"silencedetect=noise={noise_db}dB:d={min_silence}", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", log)]
    total = duration(path)
    segments, cursor = [], 0.0
    for s, e in zip(starts, ends + [total]):
        if s - cursor > 0.3:  # ignore blips between back-to-back silences
            segments.append((cursor, s))
        cursor = e
    if total - cursor > 0.3:
        segments.append((cursor, total))
    return [{"id": i, "start": round(s, 2), "end": round(e, 2)} for i, (s, e) in enumerate(segments, 1)]


def padded(segments, total, pad=PAD):
    out = []
    for i, seg in enumerate(segments):
        lo = 0.0 if i == 0 else (segments[i - 1]["end"] + seg["start"]) / 2
        hi = total if i == len(segments) - 1 else (seg["end"] + segments[i + 1]["start"]) / 2
        out.append((max(lo, seg["start"] - pad), min(hi, seg["end"] + pad)))
    return out


def item_range(text):
    """"29-44", or several ranges when an item was skipped: "45-58,60-64"."""
    ids = set()
    for part in text.split(","):
        first, _, last = part.partition("-")
        ids |= set(range(int(first), int(last or first) + 1))
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("recording", type=Path)
    ap.add_argument("--segments", type=Path)
    ap.add_argument("--noise-db", type=float, default=-35)
    ap.add_argument("--min-silence", type=float, default=1.5)
    ap.add_argument("--ids", type=item_range, help="the items this recording holds, e.g. 29-44 or 45-58,60-64 (default: all)")
    ap.add_argument("--pad", type=float, default=PAD, help=f"seconds kept around each item (default {PAD})")
    args = ap.parse_args()

    references = json.loads((EVAL / "references.json").read_text())
    if args.ids:
        references = [r for r in references if r["id"] in args.ids]

    if args.segments:
        segments = json.loads(args.segments.read_text())["segments"]
    else:
        segments = detect_segments(args.recording, args.noise_db, args.min_silence)
        seg_file = EVAL / "segments" / f"{args.recording.stem}.json"
        if seg_file.exists():
            sys.exit(f"{seg_file} already exists (may be hand-edited); re-run with --segments {seg_file}")
        seg_file.parent.mkdir(parents=True, exist_ok=True)
        seg_file.write_text(json.dumps({"recording": args.recording.name, "segments": segments}, indent=2))
        print(f"wrote {seg_file}")

    if len(segments) != len(references):
        sys.exit(f"found {len(segments)} segments but {len(references)} reference items; "
                 "edit the segments file and re-run with --segments")

    clips = EVAL / "clips"
    clips.mkdir(exist_ok=True)
    manifest_file = clips / "manifest.json"
    cut_ids = {r["id"] for r in references}
    others = [m for m in json.loads(manifest_file.read_text()) if m["id"] not in cut_ids] if manifest_file.exists() else []
    manifest = []
    for ref, (start, end) in zip(references, padded(segments, duration(args.recording), args.pad)):
        clip = clips / f"{ref['id']:02d}.wav"
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", str(args.recording),
             "-ss", f"{start:.2f}", "-to", f"{end:.2f}", "-ac", "1", "-ar", "16000", str(clip)],
            check=True,
        )
        manifest.append({**ref, "audio": clip.name, "source": args.recording.name,
                         "start": round(start, 2), "end": round(end, 2)})
    rows = sorted(others + manifest, key=lambda m: m["id"])
    manifest_file.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {len(manifest)} clips to {clips} ({len(rows)} in the manifest)")


if __name__ == "__main__":
    main()
