import XCTest
@testable import UnzipperCore

final class ZipMetadataTests: XCTestCase {
    func testDetectsZipMagic() throws {
        let directory = try makeTemporaryDirectory()
        let zip = directory.appendingPathComponent("sample.zip")
        try TestSupport.zip([("a.txt", Data("hello".utf8))]).write(to: zip)
        XCTAssertTrue(ZipMetadata.isZipFile(zip))

        let text = directory.appendingPathComponent("sample.txt")
        try Data("not a zip".utf8).write(to: text)
        XCTAssertFalse(ZipMetadata.isZipFile(text))
    }

    func testReadsCompressedSizesFromCentralDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let zip = directory.appendingPathComponent("sizes.zip")
        try TestSupport.zip([
            ("a.txt", Data("hello".utf8)),
            ("folder/b.bin", Data(repeating: 0xAB, count: 100)),
            ("empty", Data())
        ]).write(to: zip)

        let sizes = ZipMetadata.compressedSizes(at: zip)
        XCTAssertEqual(sizes, ["a.txt": 5, "folder/b.bin": 100, "empty": 0])
    }

    func testReadsUTF8Names() throws {
        let directory = try makeTemporaryDirectory()
        let zip = directory.appendingPathComponent("unicode.zip")
        try TestSupport.zip([
            ("café/naïve.txt", Data("bonjour".utf8))
        ]).write(to: zip)

        let sizes = ZipMetadata.compressedSizes(at: zip)
        XCTAssertEqual(sizes["café/naïve.txt"], 7)
    }

    func testMissingOrBrokenFilesReturnEmpty() throws {
        let directory = try makeTemporaryDirectory()
        XCTAssertTrue(ZipMetadata.compressedSizes(at: directory.appendingPathComponent("missing.zip")).isEmpty)

        let broken = directory.appendingPathComponent("broken.zip")
        try Data("PK\u{03}\u{04}not really a zip".utf8).write(to: broken)
        XCTAssertTrue(ZipMetadata.compressedSizes(at: broken).isEmpty)
    }
}
