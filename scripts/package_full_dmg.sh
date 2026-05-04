#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="txtreadapp"
SCHEME="TxtReadApp"
PROJECT="TxtReadApp.xcodeproj"
DERIVED_DATA="${DERIVED_DATA:-/tmp/TxtReadAppDerivedDataFullRelease}"
CONDA_ENV_PATH="${TXTREAD_TTS_ENV:-${TXTVOICE_TTS_ENV:-/opt/homebrew/Caskroom/miniforge/base/envs/txtnovelreader-kokoro}}"
HF_CACHE_ROOT="${HF_CACHE_ROOT:-$HOME/.cache/huggingface}"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ROOT="$ROOT_DIR/build/full-dmg"
LOCAL_TTS_ROOT_NAME="LocalTTS"
KOKORO_REQUIRED_VOICES=(
  zf_xiaoxiao
  zm_yunxi
  zm_yunjian
  zf_xiaobei
)

if [[ ! -x "$CONDA_ENV_PATH/bin/python" ]]; then
  echo "Missing bundled TTS Python env: $CONDA_ENV_PATH" >&2
  echo "Set TXTREAD_TTS_ENV to a prepared env containing kokoro." >&2
  exit 1
fi

echo "Warming Kokoro model cache for bundled voices..."
VOICE_WARM_INPUT="$(mktemp /tmp/txtreadapp-kokoro-warm.XXXXXX.txt)"
VOICE_WARM_OUTPUT="$(mktemp /tmp/txtreadapp-kokoro-warm.XXXXXX.wav)"
printf "你好，这是 TxtReadApp 本地音色缓存准备。" > "$VOICE_WARM_INPUT"
for voice in "${KOKORO_REQUIRED_VOICES[@]}"; do
  echo "  - $voice"
  "$CONDA_ENV_PATH/bin/python" \
    "$ROOT_DIR/scripts/local_tts_kokoro.py" \
    --input "$VOICE_WARM_INPUT" \
    --output "$VOICE_WARM_OUTPUT" \
    --voice "$voice" \
    --speed 1.0
done
rm -f "$VOICE_WARM_INPUT" "$VOICE_WARM_OUTPUT"

echo "Building Release app..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing built app: $APP_PATH" >&2
  exit 1
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/dmg-root" "$DIST_DIR"

echo "Staging app bundle..."
ditto "$APP_PATH" "$BUILD_ROOT/dmg-root/$APP_NAME.app"
LOCAL_TTS_ROOT="$BUILD_ROOT/dmg-root/$APP_NAME.app/Contents/Resources/$LOCAL_TTS_ROOT_NAME"
mkdir -p "$LOCAL_TTS_ROOT/scripts"

echo "Bundling Kokoro adapter script..."
ditto "$ROOT_DIR/scripts/local_tts_kokoro.py" "$LOCAL_TTS_ROOT/scripts/local_tts_kokoro.py"
chmod +x "$LOCAL_TTS_ROOT/scripts/local_tts_"*.py

echo "Bundling Python env: $CONDA_ENV_PATH"
ditto "$CONDA_ENV_PATH" "$LOCAL_TTS_ROOT/python-env"
find "$LOCAL_TTS_ROOT/python-env" \
  \( -name '__pycache__' -o -name '.pytest_cache' -o -name 'tests' -o -name 'test' \) \
  -type d -prune -exec rm -rf {} +
find "$LOCAL_TTS_ROOT/python-env" \
  \( -name '*.pyc' -o -name '*.pyo' -o -name '.DS_Store' \) \
  -type f -delete

if [[ -d "$HF_CACHE_ROOT/hub/models--hexgrad--Kokoro-82M" ]]; then
  echo "Bundling Kokoro Hugging Face cache..."
  mkdir -p "$LOCAL_TTS_ROOT/huggingface/hub"
  ditto "$HF_CACHE_ROOT/hub/models--hexgrad--Kokoro-82M" \
    "$LOCAL_TTS_ROOT/huggingface/hub/models--hexgrad--Kokoro-82M"
else
  echo "Missing Kokoro Hugging Face cache: $HF_CACHE_ROOT/hub/models--hexgrad--Kokoro-82M" >&2
  exit 1
fi

KOKORO_SNAPSHOT_ROOT="$LOCAL_TTS_ROOT/huggingface/hub/models--hexgrad--Kokoro-82M/snapshots"
for voice in "${KOKORO_REQUIRED_VOICES[@]}"; do
  if ! find "$KOKORO_SNAPSHOT_ROOT" \( -path "*/voices/$voice.pt" -type f -o -path "*/voices/$voice.pt" -type l \) | grep -q .; then
    echo "Missing bundled Kokoro voice: $voice" >&2
    exit 1
  fi
done

cat > "$LOCAL_TTS_ROOT/README.txt" <<'EOF'
TxtReadApp bundled local TTS runtime

This directory contains:
- python-env: bundled Python runtime and Python packages.
- scripts: Kokoro adapter script.
- huggingface: cached Kokoro model files.

The app prefers this bundled runtime. If it is removed, local neural TTS falls
back to the developer machine path configured in source defaults.
EOF

ln -s /Applications "$BUILD_ROOT/dmg-root/Applications"

SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
if ! git diff --quiet || ! git diff --cached --quiet; then
  SHORT_SHA="${SHORT_SHA}-dirty"
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
DMG_PATH="$DIST_DIR/$APP_NAME-full-${SHORT_SHA}-${STAMP}.dmg"

echo "Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$BUILD_ROOT/dmg-root" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created: $DMG_PATH"
du -sh "$DMG_PATH"
