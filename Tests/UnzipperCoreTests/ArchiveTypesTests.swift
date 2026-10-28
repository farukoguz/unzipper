import XCTest
@testable import UnzipperCore

final class ArchiveTypesTests: XCTestCase {
    func testEntryRatio() {
        let entry = TestSupport.entry(id: 0, path: "file", size: 100, packed: 25)
        XCTAssertEqual(entry.ratio, 0.25)
        XCTAssertNil(TestSupport.entry(id: 0, path: "file", size: 0, packed: 1).ratio)
        XCTAssertNil(TestSupport.entry(id: 0, path: "file", size: 100, packed: 0).ratio)
        XCTAssertNil(TestSupport.entry(id: 0, path: "file", size: 100, packed: nil).ratio)
    }

    func testProgressFractionUsesBytesWhenAvailable() {
        let update = ProgressUpdate(currentPath: "a", completedBytes: 50, totalBytes: 100,
                                    entriesDone: 1, entriesTotal: 4)
        XCTAssertEqual(update.fraction, 0.5)
    }

    func testProgressFractionFallsBackToEntries() {
        let update = ProgressUpdate(currentPath: "a", completedBytes: 0, totalBytes: 0,
                                    entriesDone: 1, entriesTotal: 4)
        XCTAssertEqual(update.fraction, 0.25)
    }

    func testProgressFractionIsClamped() {
        let over = ProgressUpdate(currentPath: "a", completedBytes: 150, totalBytes: 100,
                                  entriesDone: 4, entriesTotal: 4)
        XCTAssertEqual(over.fraction, 1)

        let under = ProgressUpdate(currentPath: "a", completedBytes: -10, totalBytes: 100,
                                   entriesDone: 0, entriesTotal: 4)
        XCTAssertEqual(under.fraction, 0)

        let nothing = ProgressUpdate(currentPath: "", completedBytes: 0, totalBytes: 0,
                                     entriesDone: 0, entriesTotal: 0)
        XCTAssertEqual(nothing.fraction, 0)
    }

    func testFormatMetadata() {
        XCTAssertEqual(ArchiveFormat.zip.identifier, "zip")
        XCTAssertEqual(ArchiveFormat.sevenZip.identifier, "7z")
        XCTAssertEqual(ArchiveFormat.tarGz.identifier, "tar.gz")
        XCTAssertEqual(ArchiveFormat.zip.displayName, "ZIP")
        XCTAssertEqual(ArchiveFormat.sevenZip.displayName, "7Z")
        XCTAssertEqual(ArchiveFormat.tarGz.displayName, "TAR.GZ")
        XCTAssertEqual(ArchiveFormat.zip.fileExtension, "zip")
        XCTAssertEqual(ArchiveFormat.allCases.count, 3)
    }

    func testListingDisplayFormat() {
        let listing = ArchiveListing(url: URL(fileURLWithPath: "/tmp/a.zip"),
                                     entries: [],
                                     formatName: "ZIP",
                                     filterName: "none",
                                     totalSize: 0,
                                     totalCompressed: nil,
                                     containsEncryptedEntries: false)
        XCTAssertEqual(listing.displayFormat, "ZIP")

        let compressed = ArchiveListing(url: URL(fileURLWithPath: "/tmp/a.tgz"),
                                        entries: [],
                                        formatName: "TAR",
                                        filterName: "gzip",
                                        totalSize: 0,
                                        totalCompressed: nil,
                                        containsEncryptedEntries: false)
        XCTAssertEqual(compressed.displayFormat, "TAR · GZIP")
    }

    func testCancelFlag() {
        let flag = CancelFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    func testErrorDescriptions() {
        XCTAssertEqual(ArchiveError.cancelled.errorDescription, "The operation was cancelled.")
        XCTAssertEqual(ArchiveError.message("boom").errorDescription, "boom")
    }
}
