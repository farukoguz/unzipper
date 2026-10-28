#!/bin/bash
set -euo pipefail

# Build Unzipper.app into ./dist without requiring Xcode.
# Usage: ./build.sh [debug|release]   (default: release)

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Unzipper"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building $APP_NAME ($CONFIG)"
swift build --product "$APP_NAME" -c "$CONFIG"

BIN="$(swift build --product "$APP_NAME" -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

if [[ ! -f "Resources/Unzipper.icns" ]]; then
    echo "==> Generating app icon"
    swift Tools/GenerateIcon.swift Resources
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/Unzipper.icns" "$APP/Contents/Resources/Unzipper.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so macOS treats the bundle as a proper app.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

# Refresh Launch Services so Finder picks up the icon and document types.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "==> Built $APP"
