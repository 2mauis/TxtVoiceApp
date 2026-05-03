# txtnovelreader

A SwiftUI macOS app for importing local .txt novels and reading them aloud.

---

After finishing the anime *Eternal Life* on Bilibili, I felt bored. I didn’t want to read a novel, just listen to one. I also didn’t want to go through the trouble of setting up TTS on my phone, so I urged Codex to write it for me.

This is also for fellow novel readers and anime fans.

---

追毕永生之剧于B站，感到寂寞，不欲读书，惟欲听之。又不欲自行折腾手机之语音合成，遂督促Codex为我所作。此亦献给书友与剧友。

## Current Scope

- Import TXT files from the Mac file picker.
- Decode UTF-8, UTF-16, GB18030/GBK, and Big5 text.
- Persist imported books in the app sandbox.
- Detect common Chinese and English chapter headings.
- Read selected chapters with playback controls, previous/next chapter navigation,
  and saved reading state.
- Generate and cache chapter audio in the background to reduce playback stalls.
- Default to macOS system speech for zero setup local playback.
- Optional local/offline TTS through command adapters:
  - Kokoro for lighter local speech generation.
  - Chatterbox for heavier multilingual voice generation.
- Voice presets for female, male, deeper male, mature female, and custom voices
  where the selected backend supports them.

## License

txtnovelreader is licensed under the Apache License, Version 2.0. See
[`LICENSE`](LICENSE).

## Local TTS Commands

The app intentionally does not use Ollama/Gemma as TTS engines. They generate
text, not audio. Local neural speech is integrated through dedicated local
backend commands. The app passes one chapter chunk at a time to the backend and
plays the generated audio after it is written to disk.

The command contract is:

```text
--input {input} --output {output}
```

txtnovelreader writes UTF-8 text to `{input}` and plays the audio file written to
`{output}`. The app also supports placeholders such as `{voice}`, `{speed}`,
`{chatterboxVoice}`, `{exaggeration}`, and `{cfgWeight}` in the argument
template.

### Kokoro

Create the conda environment:

```sh
conda create -n txtvoice-tts -c conda-forge --override-channels python=3.11 -y
conda run -n txtvoice-tts python -m pip install "kokoro>=0.9.4" soundfile "misaki[zh]>=0.9.4"
```

App settings:

```text
引擎: Kokoro 本地 TTS
命令: /opt/homebrew/Caskroom/miniforge/base/envs/txtvoice-tts/bin/python
参数模板: /path/to/txtnovelreader/scripts/local_tts_kokoro.py --input {input} --output {output} --voice {voice} --speed {speed}
```

Kokoro is lighter and useful for validating the offline pipeline. Judge Chinese
novel narration quality by listening tests before making it the only option.

### Chatterbox

Install inside the same conda environment if you want to compare a heavier
multilingual model:

```sh
conda run -n txtvoice-tts python -m pip install chatterbox-tts
```

App settings:

```text
引擎: Chatterbox 本地 TTS
命令: /opt/homebrew/Caskroom/miniforge/base/envs/txtvoice-tts/bin/python
参数模板: /path/to/txtnovelreader/scripts/local_tts_chatterbox.py --input {input} --output {output} --model multilingual --language zh --voice {chatterboxVoice} --exaggeration {exaggeration} --cfg-weight {cfgWeight}
```

Chinese/multilingual defaults are built into the adapter:

```sh
conda run -n txtvoice-tts python scripts/local_tts_chatterbox.py --input input.txt --output output.wav --model multilingual --language zh
```

## Removed Paths

Earlier experiments with app-bundled language models and local text-generation
engines were removed from the app surface. They were not reliable speech
engines for this project. The maintained paths are now macOS system speech,
Kokoro local command, and Chatterbox local command.

## Build And Run

Command-line build:

```sh
xcodebuild -project TxtVoiceApp.xcodeproj -scheme TxtVoiceApp -sdk macosx -configuration Debug -derivedDataPath /private/tmp/TxtVoiceMacDerivedData build
```

Run:

```sh
open /private/tmp/TxtVoiceMacDerivedData/Build/Products/Debug/txtnovelreader.app
```

Verified app artifact:

```text
/private/tmp/TxtVoiceMacDerivedData/Build/Products/Debug/txtnovelreader.app
```
