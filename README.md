# Unzipper

A fast, native macOS archive utility with a WinRAR-style browser. Open an
archive, navigate its folders, preview entries, extract what you need, or create
new archives — all with a keyboard-friendly SwiftUI interface and no external
dependencies.

## Features

- **Browse before extracting** — folder tree, breadcrumbs, sortable columns
  (name, size, packed size, ratio, modified date), and instant search across the
  whole archive.
- **Extract everything or just a selection** — double-click folders to navigate,
  ⌘E to extract all, ⇧⌘E for the selection. Encrypted ZIPs prompt for a password.
- **Quick Look** — ⌘Y extracts a single entry to a temporary folder and previews
  it with the native Quick Look panel.
- **Create archives** — ZIP, 7Z, and TAR.GZ with Store/Fast/Normal/Maximum
  compression. Drag files or folders onto the window, or use *New Archive…*.
- **Fast, native pipeline** — batch extraction/creation on background tasks with
  live progress, throughput, ETA, and cancellation. No helper processes or
  Finder round-trips.
- **Security first** — paths are normalized (`..` and absolute paths removed),
  symlink traversal is blocked, and existing files are only replaced when
  *Overwrite* is on.
- **Small touches** — drag-and-drop opening, recent archives, Finder reveal,
  archive document types, and a generated app icon.

## Supported formats

| | Read | Write |
|---|---|---|
| ZIP / ZIPX / JAR | ✅ | ✅ |
| 7Z | ✅ | ✅ |
| TAR, TAR.GZ, TAR.BZ2, TAR.XZ | ✅ | TAR.GZ |
| GZIP, BZIP2, XZ | ✅ | — |
| RAR (v4/v5) | ✅ | — |
| CAB, ISO | ✅ | — |

Reading is provided by the system `libarchive`; RAR creation is intentionally not
supported.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)

The app is built with Swift Package Manager and a small C shim over the system
`libarchive`, so no Homebrew packages or Xcode project are required.

## Build and run

```bash
./build.sh              # release build + dist/Unzipper.app
./build.sh debug        # debug build
open dist/Unzipper.app
```

`build.sh` compiles the SwiftPM product, assembles the `.app` bundle, copies the
icon and `Info.plist`, and ad-hoc signs the result. The bundle is self-contained:
copy `dist/Unzipper.app` to `/Applications` if you like.

To regenerate the icon:

```bash
swift Tools/GenerateIcon.swift Resources
```

## Usage

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

You can also drop an archive on the window to open it, or drop files/folders to
start a new archive. The archive table supports the usual multi-selection,
sorting by clicking column headers, and right-click actions.

## Project layout

```
Sources/
  CSArchive/        C shim over libarchive (list, extract, create)
  UnzipperCore/     Swift models, ZIP metadata parser, async services
  Unzipper/         SwiftUI app (browser, sheets, jobs, Quick Look)
Tests/
  CoreTest/         CLI harness for list/extract/create
  ctest.c           Low-level C engine test
Tools/
  GenerateIcon.swift
```

## Notes and limitations

- Extraction and creation run against the system `libarchive`; the exact list of
  readable formats depends on the macOS version.
- Archives with encrypted *headers* (rather than encrypted entries) cannot be
  listed without a password, because listing happens before the password prompt.
- Compressed single files (for example `notes.txt.gz` created with `gzip`) are
  not browsable; use tar-based `.tar.gz`/`.tgz` archives instead.
- The app is ad-hoc signed for local use. If you distribute it, sign with a
  Developer ID certificate and notarize it to satisfy Gatekeeper.
- The release build targets the host architecture by default. For a universal
  binary, run `swift build -c release --arch arm64 --arch x86_64` and update
  `build.sh` to point at the resulting product.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
