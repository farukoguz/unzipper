import XCTest
@testable import UnzipperCore

final class FormattingTests: XCTestCase {
    func testRatio() {
        XCTAssertEqual(Formatting.ratio(100, 40), "60%")
        XCTAssertEqual(Formatting.ratio(100, 100), "0%")
        XCTAssertEqual(Formatting.ratio(100, 150), "0%")
        XCTAssertEqual(Formatting.ratio(0, 10), "—")
        XCTAssertEqual(Formatting.ratio(100, nil), "—")
        XCTAssertEqual(Formatting.ratio(100, 0), "—")
    }

    func testSizePlaceholders() {
        XCTAssertEqual(Formatting.size(nil), "—")
        XCTAssertEqual(Formatting.size(0), "Zero bytes")
        XCTAssertEqual(Formatting.compactSize(nil), "—")
        XCTAssertEqual(Formatting.compactSize(0), "0")
    }

    func testItemsPluralization() {
        XCTAssertEqual(Formatting.items(0), "0 items")
        XCTAssertEqual(Formatting.items(1), "1 item")
        XCTAssertEqual(Formatting.items(2), "2 items")
    }

    func testDatePlaceholders() {
        XCTAssertEqual(Formatting.date(nil), "—")
        XCTAssertEqual(Formatting.tableDate(nil), "—")
    }
}
