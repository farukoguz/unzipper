#!/bin/bash
set -euo pipefail

# Build Unzipper.app into ./dist without requiring Xcode.
#
# Usage: ./build.sh [debug|release] [--universal]
#
#   --universal  build both arm64 and x86_64 slices and combine them with lipo.
#                Release artifacts should use this so the app runs on Intel Macs.

cd "$(dirname "$0")"

CONFIG="${1:-release}"
UNIVERSAL="${2:-}"
APP_NAME="Unzipper"
DIST="dist"
APP="$DIST/$APP_NAME.app"

build_slice() {
    local arch="$1"
    echo "==> Building $APP_NAME ($CONFIG, $arch)"
    swift build --product "$APP_NAME" -c "$CONFIG" --arch "$arch"
}

if [[ "$UNIVERSAL" == "--universal" ]]; then
    build_slice arm64
    ARM_BIN="$(swift build --product "$APP_NAME" -c "$CONFIG" --arch arm64 --show-bin-path)/$APP_NAME"
    build_slice x86_64
    X86_BIN="$(swift build --product "$APP_NAME" -c "$CONFIG" --arch x86_64 --show-bin-path)/$APP_NAME"

    for bin in "$ARM_BIN" "$X86_BIN"; do
        if [[ ! -x "$bin" ]]; then
            echo "error: built binary not found at $bin" >&2
            exit 1
        fi
    done
else
    echo "==> Building $APP_NAME ($CONFIG)"
    swift build --product "$APP_NAME" -c "$CONFIG"
    BIN="$(swift build --product "$APP_NAME" -c "$CONFIG" --show-bin-path)/$APP_NAME"
    if [[ ! -x "$BIN" ]]; then
        echo "error: built binary not found at $BIN" >&2
        exit 1
    fi
fi

if [[ ! -f "Resources/Unzipper.icns" ]]; then
    echo "==> Generating app icon"
    swift Tools/GenerateIcon.swift Resources
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$UNIVERSAL" == "--universal" ]]; then
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/$APP_NAME"
    echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
else
    cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/Unzipper.icns" "$APP/Contents/Resources/Unzipper.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so macOS treats the bundle as a proper app.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

codesign --verify --deep --strict "$APP"

# Refresh Launch Services so Finder picks up the icon and document types.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "==> Built $APP"
