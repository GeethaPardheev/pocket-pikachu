#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Pocket Pikachu.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/swift-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/Resources/frames"; cp -R "$ROOT/Resources/frames" "$APP/Contents/Resources/"
cp "$ROOT/integrations/claude/bridge.py" "$APP/Contents/Resources/claude-bridge.py"
cp -R "$ROOT/Resources/terminal" "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/voice"; cp -R "$ROOT/Resources/voice" "$APP/Contents/Resources/"
xcrun swiftc "$ROOT/Sources/"*.swift -o "$APP/Contents/MacOS/PocketPikachu" -framework AppKit -framework ApplicationServices -framework CoreAudio -framework WebKit -framework AVFoundation -framework Security -module-cache-path "$ROOT/build/swift-cache"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
