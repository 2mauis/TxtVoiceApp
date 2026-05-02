# TxtVoiceApp

A SwiftUI macOS app for importing local .txt novels and reading them aloud.

---

After finishing the anime *Eternal Life* on Bilibili, I felt bored. I didn’t want to read a novel, just listen to one. I also didn’t want to go through the trouble of setting up TTS on my phone, so I urged Codex to write it for me.

This is also dedicated to my fish friends and fellow anime fans.

---

追毕永生之剧于B站，感到寂寞，不欲读书，惟欲听之。又不欲自行折腾手机之语音合成，遂督促Codex为我所作。此亦献鱼书友与剧友。

## Features

- Import TXT files from the Mac file picker.
- Decode UTF-8, UTF-16, GB18030/GBK, and Big5 text.
- Persist imported books in the app sandbox.
- Detect common Chinese and English chapter headings.
- Read selected chapters with playback controls.
- Default to macOS system speech for zero setup local playback.
- Optional local/offline TTS:
  - Local command adapters for Chatterbox and Kokoro.
  - Local TTS endpoint compatible with `/v1/audio/speech`.
  - Kokoro CoreML/ANE uses the upstream Swift pipeline directly from the app;
    Python is only used for offline testing or asset preparation.
- Optional vendor TTS:
  - Gemini native TTS REST API.
  - OpenAI-compatible `/v1/audio/speech` APIs.
  - Custom OpenAI-compatible endpoint for self-hosted or vendor bridges.

## License

TxtVoiceApp is licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE).

## Local TTS Commands

The app intentionally does not use Ollama/Gemma as TTS engines. They generate
text, not audio. Local neural speech is integrated through the `本地 TTS 命令`
engine or a local HTTP TTS endpoint.

The command contract is:

```text
--input {input} --output {output}
```

TxtVoiceApp writes UTF-8 text to `{input}` and plays the audio file written to
`{output}`.

### Kokoro

Create the conda environment:

```sh
conda create -n txtvoice-tts -c conda-forge --override-channels python=3.11 -y
conda run -n txtvoice-tts python -m pip install "kokoro>=0.9.4" soundfile "misaki[zh]>=0.9.4"
```

App settings:

```text
引擎: 本地 TTS 命令
命令: /opt/homebrew/bin/conda
参数模板: run -n txtvoice-tts python /Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_kokoro.py --input {input} --output {output} --voice {voice} --speed {speed}
输出扩展名: wav
```

Kokoro is lighter and useful for validating the offline pipeline. Judge Chinese
novel narration quality by listening tests before making it the only option.
TxtVoiceApp also supports `{voice}` and `{speed}` placeholders for local command
templates:

```text
参数模板: run -n txtvoice-tts python /Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_kokoro.py --input {input} --output {output} --voice {voice} --speed {speed}
```

### Chatterbox

Install inside the same conda environment if you want to compare a heavier
multilingual model:

```sh
conda run -n txtvoice-tts python -m pip install chatterbox-tts
```

App settings:

```text
引擎: 本地 TTS 命令
命令: /opt/homebrew/bin/conda
参数模板: run -n txtvoice-tts python /Volumes/DATACS/work/code/TxtVoiceApp/scripts/local_tts_chatterbox.py --input {input} --output {output}
输出扩展名: wav
```

Chinese/multilingual defaults are built into the adapter:

```sh
conda run -n txtvoice-tts python scripts/local_tts_chatterbox.py --input input.txt --output output.wav --model multilingual --language zh
```

## Build And Run

Command-line build:

```sh
xcodebuild -project TxtVoiceApp.xcodeproj -scheme TxtVoiceApp -sdk macosx -configuration Debug -derivedDataPath /private/tmp/TxtVoiceMacDerivedData build
```

Run:

```sh
open /private/tmp/TxtVoiceMacDerivedData/Build/Products/Debug/TxtVoiceApp.app
```

Verified app artifact:

```text
/private/tmp/TxtVoiceMacDerivedData/Build/Products/Debug/TxtVoiceApp.app
```
