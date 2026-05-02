#!/usr/bin/env python3
"""Generate speech with local Kokoro TTS for TxtVoiceApp.

Install dependency first:

    python3 -m pip install "kokoro>=0.9.4" soundfile

Kokoro is lightweight and useful for validating the local offline TTS pipeline.
Chinese narration quality should be judged by listening tests.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


os.environ.setdefault("HF_HUB_DISABLE_XET", "1")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TxtVoiceApp Kokoro TTS adapter")
    parser.add_argument("--input", required=True, help="UTF-8 text file from TxtVoiceApp")
    parser.add_argument("--output", required=True, help="Output wav file path")
    parser.add_argument("--language", default="z", help="Kokoro language code")
    parser.add_argument("--voice", default="zf_xiaoxiao", help="Kokoro voice name")
    parser.add_argument("--speed", type=float, default=1.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        import soundfile as sf
        from kokoro import KPipeline

        text = Path(args.input).read_text(encoding="utf-8").strip()
        if not text:
            print("input text is empty", file=sys.stderr, flush=True)
            return 1

        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)

        print(
            f"loading kokoro language={args.language} voice={args.voice}",
            file=sys.stderr,
            flush=True,
        )
        pipeline = KPipeline(lang_code=args.language)
        print("kokoro model loaded; generating audio", file=sys.stderr, flush=True)
        generator = pipeline(text, voice=args.voice, speed=args.speed)
        chunks = [audio for _, _, audio in generator]
        if not chunks:
            print("kokoro generated no audio", file=sys.stderr, flush=True)
            return 1

        import numpy as np

        audio = np.concatenate(chunks)
        sf.write(str(output), audio, 24000)
        print(
            f"ok model=kokoro language={args.language} voice={args.voice} "
            f"chars={len(text)} output={args.output}",
            flush=True,
        )
        return 0
    except ModuleNotFoundError as exc:
        print(
            'missing dependency. Install with: python3 -m pip install "kokoro>=0.9.4" soundfile',
            file=sys.stderr,
            flush=True,
        )
        print(str(exc), file=sys.stderr, flush=True)
        return 2
    except Exception as exc:
        print(f"kokoro adapter failed: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
