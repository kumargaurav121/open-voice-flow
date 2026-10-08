"""ovf-eval: run speech-to-text configs over the eval clips and score them.

  ovf-eval run turbo-auto trelis-hi-mixed      # writes docs/eval/clips/transcripts/<config>.json
  ovf-eval score turbo-auto trelis-hi-mixed    # prints a comparison table
  ovf-eval score --all --report docs/eval/reports/2026-10-08-bakeoff.md
"""

import argparse
import json
import time
from datetime import date
from pathlib import Path
from typing import Any

from .runners import CONFIGS
from .score import Item, Report, Transcript, score

EVAL = Path(__file__).resolve().parents[3] / "docs" / "eval"
CLIPS = EVAL / "clips"
TRANSCRIPTS = CLIPS / "transcripts"  # under clips/, so git-ignored with the audio


def _manifest() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = json.loads((CLIPS / "manifest.json").read_text())
    return rows


def _items() -> list[Item]:
    return [Item(m["id"], m["lang"], m["reference"], m.get("reference_devanagari")) for m in _manifest()]


def run(names: list[str]) -> None:
    manifest = _manifest()
    TRANSCRIPTS.mkdir(exist_ok=True)
    for name in names:
        config = CONFIGS[name]
        print(f"{name}: loading")
        transcribe = config.load()
        transcribe(CLIPS / manifest[0]["audio"], manifest[0]["lang"])  # warm-up, not timed
        results = []
        for m in manifest:
            started = time.perf_counter()
            text = transcribe(CLIPS / m["audio"], m["lang"])
            seconds = time.perf_counter() - started
            results.append({"id": m["id"], "text": text, "seconds": round(seconds, 3)})
            print(f"  {m['id']:02d} {seconds:5.2f}s {text[:70]}")
        (TRANSCRIPTS / f"{name}.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))


def _load(name: str) -> list[Transcript]:
    rows = json.loads((TRANSCRIPTS / f"{name}.json").read_text())
    return [Transcript(r["id"], r["text"], r["seconds"]) for r in rows]


def _pct(value: float) -> str:
    return f"{value * 100:.1f}"


LANGUAGES = ["en", "hi", "hinglish"]


def _words(reports: dict[str, Report], lang: str) -> int:
    return next(iter(reports.values())).by_language[lang].reference_words


def _table(reports: dict[str, Report]) -> str:
    langs = LANGUAGES
    header = (
        "| Config | Overall WER (agnostic) | Overall WER (strict) | "
        + " | ".join(f"{lang} (agnostic, {_words(reports, lang)} words)" for lang in langs)
        + " | Median s | p95 s | Translated clips |"
    )
    lines = [header, "|" + "---|" * (header.count("|") - 1)]
    for name, r in reports.items():
        per_lang = " | ".join(_pct(r.by_language[lang].agnostic_wer) if lang in r.by_language else "-" for lang in langs)
        translated = ", ".join(map(str, r.translated)) or "none"
        lines.append(
            f"| {name} | {_pct(r.overall.agnostic_wer)} | {_pct(r.overall.strict_wer)} | {per_lang} | "
            f"{r.latency_median:.2f} | {r.latency_p95:.2f} | {translated} |"
        )
    return "\n".join(lines)


def _strict_check(latin: dict[str, Report], devanagari: dict[str, Report]) -> str:
    """Strict WER where script can't bias the result: English, and Hindi against Devanagari references."""
    lines = [
        f"| Config | en strict ({_words(latin, 'en')} words) | hi strict vs Devanagari refs ({_words(latin, 'hi')} words) |",
        "|---|---|---|",
    ]
    for name in latin:
        lines.append(
            f"| {name} | {_pct(latin[name].by_language['en'].strict_wer)} | "
            f"{_pct(devanagari[name].by_language['hi'].strict_wer)} |"
        )
    return "\n".join(lines)


def report_markdown(reports: dict[str, Report], devanagari_reports: dict[str, Report], *, clips: int) -> str:
    configs = "\n".join(f"- **{name}**: {CONFIGS[name].description}" for name in reports)
    return f"""# STT bake-off, {date.today().isoformat()}

{clips} clips from the personal eval set (see `docs/eval/reading-script.md`), scored against Latin-script references.
WER in %, lower is better. **Agnostic** compares sounds across scripts (Devanagari vs romanised Hindi
count as the same word) and is the headline; **strict** is the text exactly as produced, before cleanup.
Latency is per clip on this Mac outside the app, so compare it between rows, not against the in-app target.

{configs}

{_table(reports)}

**Strict cross-check.** The agnostic metric is lenient and only helps outputs that use Devanagari, so
here is strict WER where script can't bias the comparison:

{_strict_check(reports, devanagari_reports)}
"""


def score_command(names: list[str], *, devanagari: bool, report: Path | None, force: bool) -> None:
    items = _items()
    reports = {name: score(items, _load(name), devanagari_references=devanagari) for name in names}
    print(_table(reports))
    if report:
        if report.exists() and not force:
            raise SystemExit(f"{report} exists (it may hold a hand-written recommendation); pass --force to replace it")
        latin = reports if not devanagari else {n: score(items, _load(n)) for n in names}
        devanagari_reports = {n: score(items, _load(n), devanagari_references=True) for n in names}
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(report_markdown(latin, devanagari_reports, clips=len(items)))
        print(f"\nwrote {report}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="ovf-eval")
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run", help="transcribe the eval clips with one or more configs")
    run_parser.add_argument("configs", nargs="+", choices=sorted(CONFIGS))
    score_parser = sub.add_parser("score", help="score saved transcripts")
    score_parser.add_argument("configs", nargs="*", choices=sorted(CONFIGS))
    score_parser.add_argument("--all", action="store_true", help="every config with saved transcripts")
    score_parser.add_argument("--devanagari", action="store_true", help="Devanagari references for pure-Hindi items")
    score_parser.add_argument("--report", type=Path, help="also write a markdown report here")
    score_parser.add_argument("--force", action="store_true", help="overwrite an existing report")
    args = parser.parse_args()

    if args.command == "run":
        run(args.configs)
    else:
        names = [n for n in CONFIGS if (TRANSCRIPTS / f"{n}.json").exists()] if args.all else args.configs
        if not names:
            parser.error("no configs given and no saved transcripts found")
        score_command(names, devanagari=args.devanagari, report=args.report, force=args.force)


if __name__ == "__main__":
    main()
