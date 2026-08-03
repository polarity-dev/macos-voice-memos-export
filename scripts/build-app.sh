#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/.build"
APP="$ROOT/VoiceMemosExport.app"
CONTENTS="$APP/Contents"
BROKER="$CONTENTS/MacOS/VoiceMemosExport"
CLI="$BUILD/voice-memos"
ARCH=$(uname -m)
TARGET="$ARCH-apple-macos13.0"

rm -rf "$APP" "$BUILD"
mkdir -p "$CONTENTS/MacOS" "$BUILD"
cp "$ROOT/Sources/Info.plist" "$CONTENTS/Info.plist"

swiftc \
  -O \
  -warnings-as-errors \
  -target "$TARGET" \
  -o "$BROKER" \
  "$ROOT"/Sources/Shared/*.swift \
  "$ROOT"/Sources/Broker/*.swift \
  -lsqlite3

swiftc \
  -O \
  -warnings-as-errors \
  -target "$TARGET" \
  -o "$CLI" \
  "$ROOT"/Sources/Shared/*.swift \
  "$ROOT"/Sources/CLI/*.swift

codesign \
  --force \
  --sign - \
  --identifier dev.voicememosexport.cli \
  "$APP"
codesign --verify --deep --strict "$APP"

printf 'Built broker: %s\n' "$APP"
printf 'Built CLI: %s\n' "$CLI"
printf 'Grant Full Disk Access to the installed app before querying Voice Memos.\n'
