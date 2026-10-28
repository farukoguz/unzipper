#!/bin/bash
# Builds dist/Unzipper-<version>.dmg -- the installer the release page offers.
#
# A disk image rather than a zip so installing is the drag-to-Applications
# gesture: the mounted image shows the app next to an Applications shortcut, and
# dropping one on the other is the whole install. Nothing runs inside the image;
# a DMG cannot copy the app anywhere by itself, and a build that tried to would
# be behaving like the malware Gatekeeper exists to stop.
#
# The image is read back and its app signature verified before it is published,
# so a package that mounts but will not launch never leaves this script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Unzipper.app"
OUT="$ROOT/dist"

if [ ! -d "$APP" ]; then
    echo "!! nothing to package: $APP does not exist." >&2
    echo "   Run ./build.sh release --universal first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist")"
DMG="$OUT/Unzipper-$VERSION.dmg"

TEAM="$(codesign -dv "$APP" 2>&1 | sed -nE 's/^TeamIdentifier=//p' | head -1)"
if [ -n "$TEAM" ] && [ "$TEAM" != "not set" ]; then
    SIGNING="signed, Team $TEAM"
else
    SIGNING="ad-hoc"
fi

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Unzipper" 2>/dev/null || echo unknown)"

echo "==> packaging Unzipper $VERSION ($SIGNING, $ARCHS)"

# Fail here rather than ship an image that mounts to nothing.
codesign --verify --deep --strict "$APP" || {
    echo "!! the signature does not verify; refusing to package it" >&2
    exit 1
}

rm -f "$DMG" "$DMG.sha256"

STAGE="$(mktemp -d)"
RW="$STAGE.dmg"
MOUNTED="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MOUNTED" -quiet 2>/dev/null || true
    rm -rf "$STAGE" "$RW" "$MOUNTED"
}
trap cleanup EXIT

mkdir -p "$OUT"

# ditto, not cp: it preserves the bundle's symlinks, permissions and resource
# forks, which the executable bit and code signature depend on.
ditto "$APP" "$STAGE/Unzipper.app"

# The drop target. This is a link to the real folder, not a copy: the app must
# land in the user's /Applications, not inside the read-only image.
ln -s /Applications "$STAGE/Applications"

# Two passes because hdiutil cannot compress while creating from a folder: a
# read-write image first, then a compressed one. -srcfolder copies the staged
# tree with the bits a bundle needs instead of imaging a filesystem under it.
hdiutil create \
    -volname "Unzipper" \
    -fs HFS+ \
    -format UDRW \
    -srcfolder "$STAGE" \
    -ov \
    "$RW" >/dev/null

hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null

# Read it back and confirm the app inside is intact. A DMG that mounts but whose
# bundle is broken is the worst outcome: it looks fine until the user drags it.
hdiutil attach "$DMG" -mountpoint "$MOUNTED" -nobrowse -quiet
if ! codesign --verify --deep --strict "$MOUNTED/Unzipper.app" 2>/dev/null; then
    echo "!! the app inside the image does not verify; refusing to publish it" >&2
    exit 1
fi
if [ ! -L "$MOUNTED/Applications" ]; then
    echo "!! the image has no Applications shortcut; refusing to publish it" >&2
    exit 1
fi

# Written next to the image and published with it. The build is not notarised,
# so macOS cannot tell a genuine download from a tampered one; this checksum is
# the signal a user can actually check. It covers the finished image, so it also
# catches a truncated download.
CHECKSUM_FILE="$DMG.sha256"
( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$CHECKSUM_FILE")" )

echo "==> done"
echo "    $DMG"
echo "    $(du -h "$DMG" | cut -f1)"
echo "    $CHECKSUM_FILE"
echo "    $(cut -d' ' -f1 < "$CHECKSUM_FILE")"
echo
echo "Publish both files:"
echo "    git tag -a v$VERSION -m 'Version $VERSION'"
echo "    git push origin v$VERSION"
echo "    gh release create v$VERSION \\"
echo "        dist/$(basename "$DMG") \\"
echo "        dist/$(basename "$CHECKSUM_FILE")"
