import XCTest
@testable import UnzipperCore

final class ArchiveIndexTests: XCTestCase {
    private var index: ArchiveIndex!

    override func setUp() {
        super.setUp()
        index = ArchiveIndex(entries: [
            TestSupport.entry(id: 0, path: "docs", isDirectory: true),
            TestSupport.entry(id: 1, path: "docs/a.txt", size: 100, packed: 40),
            TestSupport.entry(id: 2, path: "docs/sub/b.txt", size: 200, packed: 80),
            TestSupport.entry(id: 3, path: "readme.md", size: 50, packed: 20),
            TestSupport.entry(id: 4, path: "implicit/nested/c.txt", size: 25, packed: 10),
            TestSupport.entry(id: 5, path: "empty", isDirectory: true)
        ])
    }

    func testImplicitAncestorsBecomeFolders() {
        XCTAssertEqual(index.children(of: ""), ["docs", "empty", "implicit"])
        XCTAssertEqual(index.children(of: "docs"), ["docs/sub"])
        XCTAssertEqual(index.children(of: "implicit"), ["implicit/nested"])
        XCTAssertEqual(index.children(of: "implicit/nested"), [])
        XCTAssertEqual(index.allFolders, ["docs", "docs/sub", "implicit", "implicit/nested", "empty"])
    }

    func testExplicitFolderEntriesAreTracked() {
        XCTAssertEqual(index.folderEntry(at: "docs")?.id, 0)
        XCTAssertEqual(index.folderEntry(at: "empty")?.id, 5)
        XCTAssertNil(index.folderEntry(at: "docs/sub"))
        XCTAssertNil(index.folderEntry(at: "implicit"))
    }

    func testFilesAreGroupedByParent() {
        XCTAssertEqual(index.files(in: "docs").map(\.name), ["a.txt"])
        XCTAssertEqual(index.files(in: "docs/sub").map(\.name), ["b.txt"])
        XCTAssertEqual(index.files(in: "").map(\.name), ["readme.md"])
        XCTAssertEqual(index.files(in: "implicit/nested").map(\.name), ["c.txt"])
    }

    func testFolderSizesAndCountsIncludeDescendants() {
        XCTAssertEqual(index.folderSize(""), 375)
        XCTAssertEqual(index.folderSize("docs"), 300)
        XCTAssertEqual(index.folderSize("docs/sub"), 200)
        XCTAssertEqual(index.folderSize("implicit"), 25)
        XCTAssertEqual(index.folderSize("empty"), 0)

        XCTAssertEqual(index.fileCount(inFolder: ""), 4)
        XCTAssertEqual(index.fileCount(inFolder: "docs"), 2)
        XCTAssertEqual(index.fileCount(inFolder: "docs/sub"), 1)
        XCTAssertEqual(index.fileCount(inFolder: "empty"), 0)
        XCTAssertEqual(index.totalFileCount, 4)
    }

    func testLookupByID() {
        XCTAssertEqual(index.entry(withID: 2)?.path, "docs/sub/b.txt")
        XCTAssertNil(index.entry(withID: 99))
    }

    func testIndicesForFolderRowsIncludeTheFolderAndDescendants() {
        let rows = ArchiveBrowser.rows(in: "", index: index)
        let docs = try! XCTUnwrap(rows.first { $0.path == "docs" })
        let indices = index.indices(for: [docs])
        XCTAssertEqual(indices, [0, 1, 2])
    }

    func testIndicesForFileRowsDoNotExpandPrefixes() {
        // A file whose path is a prefix of another entry must not drag that entry in.
        let prefixed = ArchiveIndex(entries: [
            TestSupport.entry(id: 0, path: "a", size: 1),
            TestSupport.entry(id: 1, path: "a/b.txt", size: 2)
        ])
        let row = ArchiveRow(path: "a", name: "a", isDirectory: false,
                             size: 1, packedSize: nil, modified: nil,
                             isEncrypted: false, entryIndex: 0)
        XCTAssertEqual(prefixed.indices(for: [row]), [0])
    }

    func testEmptyArchive() {
        let empty = ArchiveIndex(entries: [])
        XCTAssertTrue(empty.children(of: "").isEmpty)
        XCTAssertTrue(empty.files(in: "").isEmpty)
        XCTAssertEqual(empty.folderSize(""), 0)
        XCTAssertEqual(empty.totalFileCount, 0)
    }

    func testFolderSizesIgnoreExplicitDirectoryEntrySizes() {
        let sized = ArchiveIndex(entries: [
            TestSupport.entry(id: 0, path: "docs", isDirectory: true, size: 4096),
            TestSupport.entry(id: 1, path: "docs/a.txt", size: 100),
            TestSupport.entry(id: 2, path: "docs/sub", isDirectory: true, size: 512)
        ])
        XCTAssertEqual(sized.folderSize("docs"), 100)
        XCTAssertEqual(sized.folderSize("docs/sub"), 0)
        XCTAssertEqual(sized.folderSize(""), 100)
    }
}
