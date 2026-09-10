#!/bin/zsh
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Translex.app"

cd "$ROOT"
swift build -c "$CONFIG"
"$ROOT/Scripts/generate_icon.sh" >/dev/null
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TranslexApp" "$APP/Contents/MacOS/Translex"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Translex.icns" "$APP/Contents/Resources/Translex.icns"
chmod +x "$APP/Contents/MacOS/Translex"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "$APP"
