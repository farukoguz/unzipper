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

## Install

Download **Unzipper** from
[Releases](https://github.com/farukoguz/unzipper/releases) and open the disk image.

1. Check the image before opening it — the build is not notarised, so macOS has no
   way to tell you whether what you downloaded is what was published:

   ```sh
   shasum -a 256 -c Unzipper-*.dmg.sha256   # run in ~/Downloads
   ```

   The filename has to match the checksum exactly. A mismatch means the download
   is truncated or altered — do not open it. The `.sha256` file sits next to the
   image on the release page.
2. Drag **Unzipper** onto the **Applications** shortcut, then eject the disk.
3. Clear the quarantine flag. macOS refuses this unnotarised build before
   anything inside it gets a chance to run:

   ```sh
   /usr/bin/xattr -cr /Applications/Unzipper.app
   ```

   Then launch Unzipper normally.

   This removes macOS's record of where the app came from, so it can no longer
   warn you about an unnotarised build. Only run it on an app you built yourself
   or checked against the release checksum.

   Prefer the mouse? Try to open Unzipper once, click **Done** on the warning,
   then go to System Settings → Privacy & Security and click **Open Anyway** next
   to the message about Unzipper. (On macOS 14, right-click → **Open** also works;
   macOS 15 and later removed that shortcut.)

Requires **macOS 14 (Sonoma) or newer**.

## Build and run

Building needs the Xcode Command Line Tools (`xcode-select --install`), but no
Homebrew packages and no Xcode project.

```bash
./build.sh                     # release build for this Mac + dist/Unzipper.app
./build.sh debug               # debug build
./build.sh release --universal # arm64 + x86_64 for distribution
open dist/Unzipper.app
```

`build.sh` compiles the SwiftPM product, assembles the `.app` bundle, copies the
icon and `Info.plist`, and ad-hoc signs the result. To produce the release disk
image and checksum:

```bash
Scripts/make-dmg.sh            # dist/Unzipper-<version>.dmg + .sha256
```

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
- Local builds target the host architecture by default. The published release is
  universal: `./build.sh release --universal` builds both slices and combines
  them with `lipo`.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
