import XCTest
@testable import UnzipperCore

final class ArchivePathTests: XCTestCase {
    func testComponentsIgnoreEmptySegments() {
        XCTAssertEqual(ArchivePath.components(of: "docs/sub/file.txt"),
                       ["docs", "sub", "file.txt"])
        XCTAssertEqual(ArchivePath.components(of: "/docs//sub/"), ["docs", "sub"])
        XCTAssertEqual(ArchivePath.components(of: ""), [])
    }

    func testNameAndParent() {
        XCTAssertEqual(ArchivePath.name(of: "docs/sub/file.txt"), "file.txt")
        XCTAssertEqual(ArchivePath.name(of: "docs"), "docs")
        XCTAssertEqual(ArchivePath.parent(of: "docs/sub/file.txt"), "docs/sub")
        XCTAssertEqual(ArchivePath.parent(of: "docs"), "")
        XCTAssertEqual(ArchivePath.parent(of: ""), "")
    }

    func testAncestors() {
        XCTAssertEqual(ArchivePath.ancestors(of: "a/b/c.txt"), ["a/b", "a", ""])
        XCTAssertEqual(ArchivePath.ancestors(of: "file.txt"), [""])
        XCTAssertEqual(ArchivePath.ancestors(of: "a"), [""])
    }

    func testBreadcrumbs() {
        let crumbs = ArchivePath.breadcrumbs(for: "a/b/c")
        XCTAssertEqual(crumbs.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(crumbs.map(\.path), ["a", "a/b", "a/b/c"])
        XCTAssertTrue(ArchivePath.breadcrumbs(for: "").isEmpty)
    }
}
