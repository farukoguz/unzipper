import XCTest
@testable import UnzipperCore

final class ArchiveServiceTests: XCTestCase {
    func testCreateListExtractRoundTripForEveryWritableFormat() async throws {
        let directory = try makeTemporaryDirectory()
        let source = try makePayload(in: directory)

        for format in ArchiveFormat.allCases {
            let archive = directory.appendingPathComponent("roundtrip.\(format.fileExtension)")
            let created = try await ArchiveService.create(
                CreationRequest(destination: archive,
                                items: [source],
                                format: format,
                                compressionLevel: 6),
                cancelFlag: CancelFlag(),
                progress: { _ in })
            XCTAssertEqual(created, archive)
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path), format.identifier)

            let listing = try await ArchiveService.list(url: archive)
            XCTAssertFalse(listing.formatName.isEmpty, format.identifier)
            let paths = Set(listing.entries.map(\.path))
            XCTAssertTrue(paths.contains("payload/hello.txt"), format.identifier)
            XCTAssertTrue(paths.contains("payload/nested/inner.txt"), format.identifier)
            XCTAssertEqual(listing.totalSize, 16, format.identifier)
            XCTAssertFalse(listing.containsEncryptedEntries)

            let destination = directory.appendingPathComponent("out-\(format.identifier)")
            try await ArchiveService.extract(
                ExtractionRequest(archiveURL: archive,
                                  destination: destination,
                                  entryIndices: listing.entries.map(\.id),
                                  totalEntries: listing.entries.count,
                                  password: nil,
                                  overwrite: true,
                                  totalBytes: listing.totalSize),
                cancelFlag: CancelFlag(),
                progress: { _ in })

            XCTAssertEqual(try read(destination.appendingPathComponent("payload/hello.txt")),
                           "hello world", format.identifier)
            XCTAssertEqual(try read(destination.appendingPathComponent("payload/nested/inner.txt")),
                           "inner", format.identifier)
        }
    }

    func testZipListingHasPackedSizes() async throws {
        let directory = try makeTemporaryDirectory()
        let source = try makePayload(in: directory)
        let archive = directory.appendingPathComponent("packed.zip")
        _ = try await ArchiveService.create(
            CreationRequest(destination: archive,
                            items: [source],
                            format: .zip,
                            compressionLevel: 6),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        let listing = try await ArchiveService.list(url: archive)
        let files = listing.entries.filter { !$0.isDirectory }
        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(files.allSatisfy { $0.compressedSize != nil })
        XCTAssertNotNil(listing.totalCompressed)
        XCTAssertEqual(listing.totalCompressed, files.compactMap(\.compressedSize).reduce(0, +))
    }

    func testSelectedExtractionOnlyWritesRequestedEntry() async throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try TestSupport.write("hello", to: file)
        let archive = directory.appendingPathComponent("one.zip")
        _ = try await ArchiveService.create(
            CreationRequest(destination: archive, items: [file], format: .zip, compressionLevel: 6),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        let listing = try await ArchiveService.list(url: archive)
        let entry = try XCTUnwrap(listing.entries.first)
        let destination = directory.appendingPathComponent("selected")
        try await ArchiveService.extract(
            ExtractionRequest(archiveURL: archive,
                              destination: destination,
                              entryIndices: [entry.id],
                              totalEntries: 1,
                              password: nil,
                              overwrite: true,
                              totalBytes: entry.size),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        XCTAssertEqual(try read(destination.appendingPathComponent("hello.txt")), "hello")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
    }

    func testOverwriteFlagControlsReplacement() async throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try TestSupport.write("new", to: file)
        let archive = directory.appendingPathComponent("overwrite.zip")
        _ = try await ArchiveService.create(
            CreationRequest(destination: archive, items: [file], format: .zip, compressionLevel: 6),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        let listing = try await ArchiveService.list(url: archive)
        let destination = directory.appendingPathComponent("overwrite-out")
        let existing = destination.appendingPathComponent("hello.txt")
        try TestSupport.write("old", to: existing)

        let request = ExtractionRequest(archiveURL: archive,
                                        destination: destination,
                                        entryIndices: listing.entries.map(\.id),
                                        totalEntries: listing.entries.count,
                                        password: nil,
                                        overwrite: false,
                                        totalBytes: listing.totalSize)
        try await ArchiveService.extract(request, cancelFlag: CancelFlag(), progress: { _ in })
        XCTAssertEqual(try read(existing), "old")

        let overwrite = ExtractionRequest(archiveURL: archive,
                                          destination: destination,
                                          entryIndices: listing.entries.map(\.id),
                                          totalEntries: listing.entries.count,
                                          password: nil,
                                          overwrite: true,
                                          totalBytes: listing.totalSize)
        try await ArchiveService.extract(overwrite, cancelFlag: CancelFlag(), progress: { _ in })
        XCTAssertEqual(try read(existing), "new")
    }

    func testExtractionCreatesDestinationFolder() async throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try TestSupport.write("hello", to: file)
        let archive = directory.appendingPathComponent("folder.zip")
        _ = try await ArchiveService.create(
            CreationRequest(destination: archive, items: [file], format: .zip, compressionLevel: 6),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        let listing = try await ArchiveService.list(url: archive)
        let destination = directory.appendingPathComponent("does/not/exist/yet")
        try await ArchiveService.extract(
            ExtractionRequest(archiveURL: archive,
                              destination: destination,
                              entryIndices: listing.entries.map(\.id),
                              totalEntries: listing.entries.count,
                              password: nil,
                              overwrite: true,
                              totalBytes: listing.totalSize),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("hello.txt").path))
    }

    func testCancellation() async throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try TestSupport.write("hello", to: file)
        let archive = directory.appendingPathComponent("cancel.zip")

        let cancelledCreate = CancelFlag()
        cancelledCreate.cancel()
        do {
            _ = try await ArchiveService.create(
                CreationRequest(destination: archive, items: [file], format: .zip, compressionLevel: 6),
                cancelFlag: cancelledCreate,
                progress: { _ in })
            XCTFail("expected cancellation")
        } catch ArchiveError.cancelled {
            // expected
        }

        _ = try await ArchiveService.create(
            CreationRequest(destination: archive, items: [file], format: .zip, compressionLevel: 6),
            cancelFlag: CancelFlag(),
            progress: { _ in })
        let listing = try await ArchiveService.list(url: archive)
        let cancelledExtract = CancelFlag()
        cancelledExtract.cancel()
        do {
            try await ArchiveService.extract(
                ExtractionRequest(archiveURL: archive,
                                  destination: directory.appendingPathComponent("cancelled"),
                                  entryIndices: listing.entries.map(\.id),
                                  totalEntries: listing.entries.count,
                                  password: nil,
                                  overwrite: true,
                                  totalBytes: listing.totalSize),
                cancelFlag: cancelledExtract,
                progress: { _ in })
            XCTFail("expected cancellation")
        } catch ArchiveError.cancelled {
            // expected
        }
    }

    func testRejectsEmptyCreationAndInvalidArchive() async throws {
        let directory = try makeTemporaryDirectory()
        do {
            _ = try await ArchiveService.create(
                CreationRequest(destination: directory.appendingPathComponent("empty.zip"),
                                items: [],
                                format: .zip,
                                compressionLevel: 6),
                cancelFlag: CancelFlag(),
                progress: { _ in })
            XCTFail("expected an error")
        } catch ArchiveError.message {
            // expected
        }

        let text = directory.appendingPathComponent("not-an-archive.txt")
        try TestSupport.write("nope", to: text)
        do {
            _ = try await ArchiveService.list(url: text)
            XCTFail("expected an error")
        } catch ArchiveError.message {
            // expected
        }
    }

    func testTraversalEntriesStayInsideDestination() async throws {
        let directory = try makeTemporaryDirectory()
        let archive = directory.appendingPathComponent("traversal.zip")
        try TestSupport.zip([
            ("../escape.txt", Data("escape".utf8)),
            ("/absolute.txt", Data("absolute".utf8)),
            ("safe/../../nested.txt", Data("nested".utf8))
        ]).write(to: archive)

        let listing = try await ArchiveService.list(url: archive)
        XCTAssertEqual(Set(listing.entries.map(\.path)),
                       ["escape.txt", "absolute.txt", "nested.txt"])

        let destination = directory.appendingPathComponent("extracted")
        try await ArchiveService.extract(
            ExtractionRequest(archiveURL: archive,
                              destination: destination,
                              entryIndices: listing.entries.map(\.id),
                              totalEntries: listing.entries.count,
                              password: nil,
                              overwrite: true,
                              totalBytes: listing.totalSize),
            cancelFlag: CancelFlag(),
            progress: { _ in })

        XCTAssertEqual(try read(destination.appendingPathComponent("escape.txt")), "escape")
        XCTAssertEqual(try read(destination.appendingPathComponent("absolute.txt")), "absolute")
        XCTAssertEqual(try read(destination.appendingPathComponent("nested.txt")), "nested")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("nested.txt").path))
    }

    // MARK: - Helpers

    private func makePayload(in directory: URL) throws -> URL {
        let source = directory.appendingPathComponent("payload", isDirectory: true)
        try TestSupport.write("hello world", to: source.appendingPathComponent("hello.txt"))
        try TestSupport.write("inner", to: source.appendingPathComponent("nested/inner.txt"))
        return source
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
