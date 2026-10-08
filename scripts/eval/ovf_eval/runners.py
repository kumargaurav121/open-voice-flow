"""Speech-to-text runners for the bake-off. Each turns a clip into text.

These run outside the app (MLX / PyTorch rather than WhisperKit Core ML), so accuracy carries
over but latency only compares models relative to each other. Ticket 03 measures in-app speed.
"""

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# (clip path, item language) -> text. The language is only used by the oracle config.
Transcribe = Callable[[Path, str], str]


@dataclass(frozen=True)
class Config:
    name: str
    description: str
    load: Callable[[], Transcribe]


def _mlx_turbo(language: str | None) -> Callable[[], Transcribe]:
    def load() -> Transcribe:
        import mlx_whisper

        def transcribe(path: Path, _lang: str) -> str:
            result: dict[str, Any] = mlx_whisper.transcribe(
                str(path),
                path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
                language=language,
                condition_on_previous_text=False,
            )
            return str(result["text"]).strip()

        return transcribe

    return load


# Pinned model revisions (ADR 0010): a repo changing upstream must not silently change what we test.
REVISIONS = {
    "Trelis/whisper-hinglish-preview": "eab1188fd2d0",
    "Oriserve/Whisper-Hindi2Hinglish-Apex": "f3214eed20b4e4d4144e739982d911f87b9cb223",
    "Deepro713/whisper-large-v3-turbo-hinglish": "1296a060a990",
}


def _transformers(repo: str, prompt: Callable[[str], list[str] | None]) -> Callable[[], Transcribe]:
    """`prompt(item_lang)` gives the forced decoder prompt tokens, or None to let the model detect."""

    def load() -> Transcribe:
        import soundfile as sf
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        dtype = torch.float16 if device == "mps" else torch.float32  # fp16 is slow or unsupported on CPU
        revision = REVISIONS[repo]
        processor = WhisperProcessor.from_pretrained(repo, revision=revision)
        # safetensors only: pickle checkpoints can run code on load. transformers' stubs mistype `.to(device)`.
        model: Any = WhisperForConditionalGeneration.from_pretrained(
            repo, revision=revision, torch_dtype=dtype, use_safetensors=True, trust_remote_code=False
        )
        model = model.to(device).eval()
        tokenizer = processor.tokenizer

        def transcribe(path: Path, lang: str) -> str:
            audio, rate = sf.read(str(path), dtype="float32")
            if rate != 16_000:
                raise ValueError(f"{path} is {rate} Hz; split.py writes 16 kHz clips")
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            if len(audio) > 30 * rate:
                raise ValueError(f"{path} is over 30 s; the feature extractor would silently truncate it")
            features = processor.feature_extractor(audio, sampling_rate=16_000, return_tensors="pt")
            features = features.input_features.to(device, dtype)
            tokens = prompt(lang)
            with torch.inference_mode():
                if tokens is None:
                    out = model.generate(input_features=features, task="transcribe", max_new_tokens=440)
                else:
                    ids = [tokenizer.convert_tokens_to_ids(t) for t in tokens]
                    out = model.generate(
                        input_features=features,
                        decoder_input_ids=torch.tensor([ids], device=device),
                        max_new_tokens=440,
                    )
            return str(tokenizer.decode(out[0], skip_special_tokens=True)).strip()

        return transcribe

    return load


_TRELIS = "Trelis/whisper-hinglish-preview"
_DEEPRO = "Deepro713/whisper-large-v3-turbo-hinglish"
_ORISERVE = "Oriserve/Whisper-Hindi2Hinglish-Apex"  # turbo architecture (4 decoder layers), Roman-script output


def _forced(language: str, *, mixedcode: bool) -> list[str]:
    middle = ["<|mixedcode|>"] if mixedcode else []
    return ["<|startoftranscript|>", f"<|{language}|>", *middle, "<|transcribe|>", "<|notimestamps|>"]


CONFIGS: dict[str, Config] = {
    c.name: c
    for c in [
        Config("turbo-auto", "Whisper large-v3-turbo, language detected (the app today)", _mlx_turbo(None)),
        Config("turbo-hi", "Whisper large-v3-turbo, Hindi forced", _mlx_turbo("hi")),
        Config(
            "trelis-hi-mixed",
            "Trelis Hinglish (large-v3), one fixed prompt: hi + mixedcode",
            _transformers(_TRELIS, lambda _lang: _forced("hi", mixedcode=True)),
        ),
        Config(
            "trelis-oracle",
            "Trelis Hinglish, told the true language (en, or hi + mixedcode). A ceiling, not shippable",
            _transformers(_TRELIS, lambda lang: _forced("en", mixedcode=False) if lang == "en" else _forced("hi", mixedcode=True)),
        ),
        Config("trelis-auto", "Trelis Hinglish, language detected", _transformers(_TRELIS, lambda _lang: None)),
        Config("oriserve-auto", "Oriserve Hinglish Apex (turbo-sized, Roman output), language detected", _transformers(_ORISERVE, lambda _lang: None)),
        Config("oriserve-hi", "Oriserve Hinglish Apex, hi forced", _transformers(_ORISERVE, lambda _lang: _forced("hi", mixedcode=False))),
        Config("oriserve-en", "Oriserve Hinglish Apex, en forced", _transformers(_ORISERVE, lambda _lang: _forced("en", mixedcode=False))),
        Config("deepro-auto", "Deepro Hinglish fine-tune of turbo, language detected", _transformers(_DEEPRO, lambda _lang: None)),
    ]
}
