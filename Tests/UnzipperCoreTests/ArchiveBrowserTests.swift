import XCTest
@testable import UnzipperCore

final class ArchiveBrowserTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private var index: ArchiveIndex!

    private let modified = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        index = ArchiveIndex(entries: [
            TestSupport.entry(id: 0, path: "docs", isDirectory: true, modified: modified),
            TestSupport.entry(id: 1, path: "docs/a.txt", size: 100, packed: 40, modified: modified),
            TestSupport.entry(id: 2, path: "docs/sub/b.txt", size: 200, packed: 80),
            TestSupport.entry(id: 3, path: "readme.md", size: 50, packed: 20, encrypted: true),
            TestSupport.entry(id: 4, path: "implicit/nested/c.txt", size: 25, packed: 10),
            TestSupport.entry(id: 5, path: "empty", isDirectory: true)
        ])
    }

    func testRootRowsSortFoldersAndFilesByName() {
        let rows = ArchiveBrowser.rows(in: "", index: index, locale: locale)
        XCTAssertEqual(rows.map(\.name), ["docs", "empty", "implicit", "readme.md"])
        XCTAssertEqual(rows.map(\.isDirectory), [true, true, true, false])
        XCTAssertEqual(rows.first { $0.name == "docs" }?.size, 300)
        XCTAssertEqual(rows.first { $0.name == "docs" }?.entryIndex, 0)
        XCTAssertNil(rows.first { $0.name == "implicit" }?.entryIndex)
        XCTAssertEqual(rows.first { $0.name == "readme.md" }?.isEncrypted, true)
    }

    func testChildFolderRows() {
        let rows = ArchiveBrowser.rows(in: "docs", index: index, locale: locale)
        XCTAssertEqual(rows.map(\.name), ["a.txt", "sub"])
        XCTAssertEqual(rows.first { $0.name == "sub" }?.size, 200)
        XCTAssertNil(rows.first { $0.name == "sub" }?.entryIndex)
    }

    func testSearchMatchesEntriesAndImplicitFolders() {
        let rows = ArchiveBrowser.rows(in: "", index: index, query: "sub", locale: locale)
        XCTAssertEqual(Set(rows.map(\.path)), ["docs/sub", "docs/sub/b.txt"])
        XCTAssertEqual(rows.first { $0.path == "docs/sub" }?.isDirectory, true)
        XCTAssertEqual(rows.first { $0.path == "docs/sub" }?.size, 200)
        XCTAssertEqual(rows.first { $0.path == "docs/sub/b.txt" }?.name, "docs/sub/b.txt")
    }

    func testSearchIsCaseInsensitiveAndTrimsWhitespace() {
        let rows = ArchiveBrowser.rows(in: "", index: index, query: "  README  ", locale: locale)
        XCTAssertEqual(rows.map(\.path), ["readme.md"])
        XCTAssertEqual(rows.first?.entryIndex, 3)
    }

    func testSearchDoesNotDuplicateExplicitFolders() {
        let rows = ArchiveBrowser.rows(in: "", index: index, query: "empty", locale: locale)
        XCTAssertEqual(rows.map(\.path), ["empty"])
        XCTAssertEqual(rows.first?.entryIndex, 5)
    }

    func testSearchOnMissingTextReturnsNothing() {
        XCTAssertTrue(ArchiveBrowser.rows(in: "", index: index, query: "zzz", locale: locale).isEmpty)
    }

    func testSortingBySizeDescending() {
        let rows = ArchiveBrowser.rows(in: "",
                                       index: index,
                                       query: "txt",
                                       sortOrder: [KeyPathComparator(\ArchiveRow.sortSize, order: .reverse)],
                                       locale: locale)
        XCTAssertEqual(rows.map(\.path), ["docs/sub/b.txt", "docs/a.txt", "implicit/nested/c.txt"])
    }

    func testSortingByModified() {
        let rows = ArchiveBrowser.rows(in: "",
                                       index: index,
                                       query: "txt",
                                       sortOrder: [KeyPathComparator(\ArchiveRow.sortModified, order: .reverse)],
                                       locale: locale)
        XCTAssertEqual(rows.first?.path, "docs/a.txt")
        XCTAssertEqual(Set(rows.dropFirst().map(\.path)),
                       ["docs/sub/b.txt", "implicit/nested/c.txt"])
    }

    func testSortKeysForMissingValues() {
        let row = ArchiveRow(path: "file", name: "file", isDirectory: false,
                             size: 0, packedSize: nil, modified: nil,
                             isEncrypted: false, entryIndex: nil, locale: locale)
        XCTAssertEqual(row.sortPacked, 0)
        XCTAssertEqual(row.sortRatio, -1)
        XCTAssertEqual(row.sortModified, .distantPast)
        XCTAssertEqual(row.sortSize, 0)
    }

    func testRatioSortKey() {
        let row = ArchiveRow(path: "file", name: "file", isDirectory: false,
                             size: 100, packedSize: 25, modified: nil,
                             isEncrypted: false, entryIndex: 1, locale: locale)
        XCTAssertEqual(row.sortRatio, 0.75, accuracy: 0.0001)
    }
}
