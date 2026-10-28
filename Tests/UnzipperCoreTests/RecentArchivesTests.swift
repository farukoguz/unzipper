import XCTest
@testable import UnzipperCore

final class RecentArchivesTests: XCTestCase {
    func testAddMovesExistingURLToFront() {
        var recents = RecentArchives()
        recents.add(URL(fileURLWithPath: "/tmp/a.zip"))
        recents.add(URL(fileURLWithPath: "/tmp/b.zip"))
        recents.add(URL(fileURLWithPath: "/tmp/a.zip"))
        XCTAssertEqual(recents.urls.map(\.lastPathComponent), ["a.zip", "b.zip"])
    }

    func testLimit() {
        var recents = RecentArchives(limit: 2)
        recents.add(URL(fileURLWithPath: "/tmp/a.zip"))
        recents.add(URL(fileURLWithPath: "/tmp/b.zip"))
        recents.add(URL(fileURLWithPath: "/tmp/c.zip"))
        XCTAssertEqual(recents.urls.map(\.lastPathComponent), ["c.zip", "b.zip"])
    }

    func testRemove() {
        var recents = RecentArchives(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip")
        ])
        recents.remove(URL(fileURLWithPath: "/tmp/a.zip"))
        XCTAssertEqual(recents.urls.map(\.lastPathComponent), ["b.zip"])
    }

    func testInitializerDeduplicatesAndStandardizes() {
        let recents = RecentArchives(urls: [
            URL(fileURLWithPath: "/tmp/a.zip"),
            URL(fileURLWithPath: "/tmp/./a.zip"),
            URL(fileURLWithPath: "/tmp/b.zip")
        ])
        XCTAssertEqual(recents.urls.map(\.lastPathComponent), ["a.zip", "b.zip"])
        XCTAssertEqual(recents.urls.first?.path, "/tmp/a.zip")
    }

    func testZeroLimitKeepsNothing() {
        var recents = RecentArchives(limit: 0)
        recents.add(URL(fileURLWithPath: "/tmp/a.zip"))
        XCTAssertTrue(recents.urls.isEmpty)
    }
}
