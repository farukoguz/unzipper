import XCTest
@testable import UnzipperCore

final class ArchiveFileTypesTests: XCTestCase {
    func testSupportedExtensions() {
        let supported = ["zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2",
                         "tbz", "tbz2", "xz", "txz", "cab", "iso", "jar"]
        for ext in supported {
            XCTAssertTrue(ArchiveFileTypes.isArchive(URL(fileURLWithPath: "/tmp/file.\(ext)")), ext)
        }
    }

    func testCaseInsensitiveMatching() {
        XCTAssertTrue(ArchiveFileTypes.isArchive(URL(fileURLWithPath: "/tmp/ARCHIVE.ZIP")))
        XCTAssertTrue(ArchiveFileTypes.isArchive(URL(fileURLWithPath: "/tmp/archive.7Z")))
    }

    func testRejectsOtherFiles() {
        XCTAssertFalse(ArchiveFileTypes.isArchive(URL(fileURLWithPath: "/tmp/file.txt")))
        XCTAssertFalse(ArchiveFileTypes.isArchive(URL(fileURLWithPath: "/tmp/file")))
    }
}
