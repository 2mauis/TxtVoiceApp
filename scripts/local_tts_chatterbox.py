#!/usr/bin/env python3
"""Generate speech with local Chatterbox TTS for txtnovelreader.

This adapter is intentionally small: txtnovelreader writes a text chunk to
--input, this script writes an audio file to --output, and the app plays it.
Install dependency first:

    python3 -m pip install chatterbox-tts

For multilingual Chinese narration, use:

    --model multilingual --language zh
"""

from __future__ import annotations

import argparse
import importlib
import os
import sys
from pathlib import Path


os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("NUMBA_CACHE_DIR", "/private/tmp/txtnovelreader-numba-cache")
os.environ.setdefault("NUMBA_DISABLE_CACHE", "1")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="txtnovelreader Chatterbox TTS adapter")
    parser.add_argument("--input", required=True, help="UTF-8 text file from txtnovelreader")
    parser.add_argument("--output", required=True, help="Output wav file path")
    parser.add_argument(
        "--model",
        choices=("auto", "standard", "multilingual", "turbo"),
        default="multilingual",
        help="Chatterbox model family",
    )
    parser.add_argument("--language", default="zh", help="Language id for multilingual model")
    parser.add_argument("--voice", default="", help="Optional reference wav for voice cloning")
    parser.add_argument("--device", default="auto", choices=("auto", "mps", "cuda", "cpu"))
    parser.add_argument("--exaggeration", type=float, default=0.5)
    parser.add_argument("--cfg-weight", type=float, default=0.5)
    return parser.parse_args()


def choose_device(value: str) -> str:
    if value != "auto":
        return value

    try:
        import torch
    except Exception:
        return "cpu"

    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def read_text(path: str) -> str:
    text = Path(path).read_text(encoding="utf-8").strip()
    if not text:
        raise SystemExit("input text is empty")
    return text


def load_model(model_name: str, device: str):
    if model_name in ("auto", "multilingual"):
        try:
            module = importlib.import_module("chatterbox.mtl_tts")
            return module.ChatterboxMultilingualTTS.from_pretrained(device=device), "multilingual"
        except Exception:
            if model_name == "multilingual":
                raise

    if model_name == "turbo":
        module = importlib.import_module("chatterbox.tts_turbo")
        return module.ChatterboxTurboTTS.from_pretrained(device=device), "turbo"

    module = importlib.import_module("chatterbox.tts")
    return module.ChatterboxTTS.from_pretrained(device=device), "standard"


def generate_audio(model, model_kind: str, text: str, args: argparse.Namespace):
    kwargs = {}
    if args.voice:
        kwargs["audio_prompt_path"] = args.voice

    if model_kind == "multilingual":
        kwargs["language_id"] = args.language
        kwargs["exaggeration"] = args.exaggeration
        kwargs["cfg_weight"] = args.cfg_weight
    elif model_kind == "standard":
        kwargs["exaggeration"] = args.exaggeration
        kwargs["cfg_weight"] = args.cfg_weight

    return model.generate(text, **kwargs)


def save_audio(output_path: str, wav, sample_rate: int) -> None:
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        import torchaudio as ta

        ta.save(str(output), wav, sample_rate)
    except Exception:
        import soundfile as sf

        array = wav.detach().cpu().numpy()
        if array.ndim == 2 and array.shape[0] <= 2:
            array = array.T
        sf.write(str(output), array, sample_rate)


def main() -> int:
    args = parse_args()
    try:
        text = read_text(args.input)
        device = choose_device(args.device)
        model, model_kind = load_model(args.model, device)
        wav = generate_audio(model, model_kind, text, args)
        save_audio(args.output, wav, model.sr)
        print(
            f"ok model={model_kind} device={device} language={args.language} "
            f"chars={len(text)} output={args.output}",
            flush=True,
        )
        return 0
    except ModuleNotFoundError as exc:
        print(
            "missing dependency. Install with: python3 -m pip install chatterbox-tts",
            file=sys.stderr,
            flush=True,
        )
        print(str(exc), file=sys.stderr, flush=True)
        return 2
    except Exception as exc:
        print(f"chatterbox adapter failed: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
