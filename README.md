# Unzipper

A fast, native macOS archive browser and extractor built with SwiftUI. No
external dependencies; archive handling uses the system frameworks.

Requires **macOS 14 or newer**.

## Features

- Browse, search, Quick Look preview, and extract archives.
- Extract everything or a selection; encrypted ZIPs prompt for a password.
- Create ZIP, 7Z, TAR.GZ, and TAR.LZ4 archives with adjustable compression.
- Background jobs with progress, throughput, ETA, and cancellation.

## Supported formats

| | Read | Write |
|---|---|---|
| ZIP / ZIPX / JAR | ✅ | ✅ |
| 7Z | ✅ | ✅ |
| TAR, TAR.GZ, TAR.BZ2, TAR.XZ, TAR.LZ4 | ✅ | TAR.GZ, TAR.LZ4 |
| GZIP, BZIP2, XZ, LZ4 | ✅ | — |
| RAR (v4/v5) | ✅ | — |
| CAB, ISO | ✅ | — |

## Install

Download the latest [release](https://github.com/farukoguz/unzipper/releases),
verify it, and drag **Unzipper** onto the **Applications** shortcut:

```sh
shasum -a 256 -c Unzipper-*.dmg.sha256
xattr -cr /Applications/Unzipper.app
```

The build is ad-hoc signed and not notarised. If macOS blocks it, allow it in
**System Settings → Privacy & Security → Open Anyway**.

## Build

Requires the Xcode Command Line Tools; running tests requires full Xcode.

```sh
./build.sh
./build.sh release --universal
swift test
Scripts/make-dmg.sh
```

## Limitations

- Encrypted archives cannot be listed without a password.
- Single compressed files such as `notes.txt.gz` or `notes.txt.lz4` are not
  browsable; use the tar variants instead.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
