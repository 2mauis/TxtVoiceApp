# TxtReadApp

A macOS TXT novel reader with persisted reading state, chapter navigation,
playback-following text, and local text-to-speech options.

After finishing the anime *Eternal Life* on Bilibili, I felt bored. I did not
want to read a novel, just listen to one, so I asked Codex to build this app.
This is also for fellow novel readers and anime fans.

追毕永生之剧于 B 站，忽觉寂寞。不欲读书，惟欲听之，遂令 Codex 作此应用。
此亦献给书友与剧友。

## Features

- Import local `.txt` novels from Finder.
- Decode UTF-8, UTF-16, GB18030/GBK, and Big5 text.
- Detect common Chinese and English chapter headings.
- Persist imported books, the last open reading window, and reading progress.
- Read continuously across chapter boundaries.
- Keep the reading window synced with playback.
- Jump to previous or next chapter.
- Return to the current playback position.
- Start playback from the current reading position.
- Use macOS system voices with no setup.
- Use Kokoro through the existing Python local runtime.
- Use Kokoro CoreML through the experimental ANE path.
- Adjust voice presets and speech speed.

## Reading And Playback Behavior

Playback is treated as the source of truth. The reader highlights the text chunk
whose audio is actually playing, then advances only after that audio finishes.
This avoids the common failure mode where text races ahead of the spoken audio.

The main play button and "Start from current reading position" prefer the
currently visible reading window or the paragraph the user tapped, so scrolling
to a new passage and pressing play starts from what is on screen instead of an
older saved progress point.

## TTS Engines

TxtReadApp does not use Ollama or Gemma as TTS engines. Those tools generate
text, not audio. The maintained speech engines are:

- macOS system speech: stable, small, and available immediately.
- Kokoro local TTS: the existing Python-backed local Kokoro runtime.
- Kokoro ANE CoreML: native Swift integration through Soniqo `speech-swift`.

The ANE engine uses `computeUnits = .all`, which lets Core ML schedule supported
model stages on Apple Neural Engine where available. The first use may download
and load model files; later syntheses in the same app process reuse the loaded
model.

## ANE Validation

The ANE path was first validated in the sibling `ane-tts-lab` project using
Soniqo `speech-swift` and Chinese Kokoro voices:

```sh
swift run ane-tts-lab --text "你好，这是中文 Core ML 语音合成测试。" --voice zf_xiaoxiao --compute-units all --output out/kokoro-zf_xiaoxiao-all.wav --no-warmup
```

Observed locally:

- Cached model load: about 34-36 seconds.
- Hot synthesis: about 0.13-0.35 seconds for short Chinese text.
- Output: 24 kHz mono WAV.

## Packages

There are two package modes:

- `app-only`: small package. It includes the app and supports macOS system
  voices plus the Swift ANE integration. Model files may be downloaded/cached on
  first ANE use.
- `full`: larger package. It bundles the Python runtime, Kokoro adapter script,
  and cached local TTS model files under
  `txtreadapp.app/Contents/Resources/LocalTTS`.

The Python Kokoro engine prefers the bundled `LocalTTS` runtime when present.

## Acknowledgements

TxtReadApp's local neural TTS work stands on the Kokoro ecosystem:
[Kokoro](https://github.com/hexgrad/kokoro) provides the small, practical
open-source TTS model family that made local novel listening realistic for this
app.

The native ANE/CoreML path uses
[Soniqo speech-swift](https://github.com/soniqo/speech-swift), which wraps a
Kokoro CoreML pipeline behind a Swift API. That project made it possible to test
a zero-Python inference path inside a macOS app and to let Core ML schedule
supported model stages on Apple Neural Engine through `computeUnits = .all`.

The Python Kokoro path remains useful as a compatibility and full-package
fallback, while the Swift ANE path is the lightweight app-only route. Thank you
to the Kokoro, speech-swift, CoreML conversion, and open-source speech
contributors for publishing the models, conversion work, runtime code, and
documentation that made this app possible.

Kokoro, speech-swift, and their model files are third-party open-source
components. Please refer to the upstream projects for their licenses, model
terms, and attribution details.

## Build

Build a normal Debug app:

```sh
xcodebuild -project TxtReadApp.xcodeproj -scheme TxtReadApp -configuration Debug -derivedDataPath /private/tmp/TxtReadAppDerivedData build
```

Build a normal Release app:

```sh
xcodebuild -project TxtReadApp.xcodeproj -scheme TxtReadApp -configuration Release -derivedDataPath /private/tmp/TxtReadAppReleaseDerivedData build
```

Build a full DMG with bundled Python local TTS runtime:

```sh
scripts/package_full_dmg.sh
```

The full packager expects a prepared local TTS environment at:

```text
/opt/homebrew/Caskroom/miniforge/base/envs/txtnovelreader-kokoro
```

Set `TXTREAD_TTS_ENV` to override that path.

## License

TxtReadApp is licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE).
