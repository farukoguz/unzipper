# Unzipper

A fast, native macOS archive utility with a WinRAR-style browser. Browse archive
folders, preview entries, extract selections, and create archives in a
keyboard-friendly SwiftUI app. No external dependencies — everything goes through
the system `libarchive`.

Requires **macOS 14 or newer**.

## Features

- Folder tree, breadcrumbs, sortable columns, and instant search.
- Extract everything or a selection; encrypted ZIPs prompt for a password.
- Quick Look previews without extracting the whole archive.
- Create ZIP, 7Z, and TAR.GZ archives with adjustable compression.
- Background jobs with progress, throughput, ETA, and cancellation.
- Path normalization, blocked symlink traversal, and opt-in overwrite.

## Supported formats

| | Read | Write |
|---|---|---|
| ZIP / ZIPX / JAR | ✅ | ✅ |
| 7Z | ✅ | ✅ |
| TAR, TAR.GZ, TAR.BZ2, TAR.XZ | ✅ | TAR.GZ |
| GZIP, BZIP2, XZ | ✅ | — |
| RAR (v4/v5) | ✅ | — |
| CAB, ISO | ✅ | — |

## Install

Download the latest [release](https://github.com/farukoguz/unzipper/releases),
verify the image, then drag **Unzipper** onto the **Applications** shortcut:

```sh
shasum -a 256 -c Unzipper-*.dmg.sha256
```

The build is ad-hoc signed, not notarised, so clear the quarantine flag before
launching:

```sh
xattr -cr /Applications/Unzipper.app
```

Alternatively, open the app once, dismiss the warning, then allow it in
**System Settings → Privacy & Security → Open Anyway**.

## Build and test

Building needs the Xcode Command Line Tools. Running the XCTest suite needs a
full Xcode install.

```sh
./build.sh                      # release build for this Mac
./build.sh debug                # debug build
./build.sh release --universal  # arm64 + x86_64
open dist/Unzipper.app

swift test
# If xcode-select points at the Command Line Tools:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

Scripts/make-dmg.sh             # dist/Unzipper-<version>.dmg + .sha256
```

CI runs `swift build` and `swift test` on every pull request and push to `main`.

## Shortcuts

| Action | Shortcut |
|---|---|
| Open archive | ⌘O |
| New archive | ⌘N |
| Extract all | ⌘E |
| Extract selected | ⇧⌘E |
| Quick Look | ⌘Y |
| Search | ⌘F |
| Enclosing folder | ⌘↑ / ⌫ |
| Open selected item | ↩ |
| Close archive | ⇧⌘W |

## Limitations

- Readable formats depend on the `libarchive` shipped with macOS.
- Archives with encrypted headers cannot be listed without a password.
- Single compressed files such as `notes.txt.gz` are not browsable; use
  `.tar.gz`/`.tgz` instead.
- Distribution outside local use needs a Developer ID signature and notarisation.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
