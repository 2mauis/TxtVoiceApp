# txtnovelreader

A macOS TXT novel reader with built-in reading state, chapter navigation, and
text-to-speech playback.

After finishing the anime *Eternal Life* on Bilibili, I felt bored. I did not
want to read a novel, just listen to one, so I asked Codex to build this app.
This is also for fellow novel readers and anime fans.

追毕永生之剧于 B 站，忽觉寂寞。不欲读书，惟欲听之，遂令 Codex 作此
应用。此亦献给书友与剧友。

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
- Use bundled local Kokoro TTS in the full DMG build.
- Adjust voice preset, speech speed, and supported backend style controls.

## Packages

There are two package modes:

- `app-only`: small package. It includes the app and supports macOS system
  voices. Local neural TTS requires an external runtime.
- `full`: larger package. It bundles the Python runtime, Kokoro adapter script,
  and cached local TTS model files under
  `txtnovelreader.app/Contents/Resources/LocalTTS`.

The app always prefers the bundled `LocalTTS` runtime when present. This is the
intended direction for release builds.

## Local TTS

txtnovelreader does not use Ollama or Gemma as TTS engines. Those tools generate
text, not audio. The maintained local speech engines are:

- macOS system speech: stable, small, and available immediately.
- Kokoro local TTS: lightweight neural speech backend.

The full package includes the local backend runtime so users do not need to
manually create a conda environment.

## Build

Build a normal Release app:

```sh
xcodebuild -project TxtVoiceApp.xcodeproj -scheme TxtVoiceApp -configuration Release -derivedDataPath /tmp/TxtVoiceMacDerivedDataRelease build
```

Build a full DMG with bundled local TTS runtime:

```sh
scripts/package_full_dmg.sh
```

The full packager expects a prepared local TTS environment at:

```text
/opt/homebrew/Caskroom/miniforge/base/envs/txtnovelreader-kokoro
```

Set `TXTVOICE_TTS_ENV` to override that path.

## GitHub Actions

The repository includes a manually triggered workflow:

```text
Actions -> Manual Build DMG -> Run workflow
```

Choose `app-only` for a small system-voice build, or `full` to build a larger
DMG that installs and bundles the local TTS runtime in CI.

## License

txtnovelreader is licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE).
