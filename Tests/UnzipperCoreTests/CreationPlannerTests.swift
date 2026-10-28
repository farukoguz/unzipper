import XCTest
@testable import UnzipperCore

final class CreationPlannerTests: XCTestCase {
    func testPlansNestedTreeWithImplicitFolders() throws {
        let directory = try makeTemporaryDirectory()
        let root = directory.appendingPathComponent("root", isDirectory: true)
        try TestSupport.write("a", to: root.appendingPathComponent("a.txt"))
        try TestSupport.write("b", to: root.appendingPathComponent("sub/b.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"),
                                                   withDestinationURL: root.appendingPathComponent("a.txt"))

        let plan = try CreationPlanner.plan(items: [root],
                                            cancelFlag: CancelFlag(),
                                            progress: { _ in })
        let paths = Set(plan.items.map(\.entryPath))
        XCTAssertEqual(paths, [
            "root", "root/a.txt", "root/sub", "root/sub/b.txt", "root/empty", "root/link"
        ])

        let rootItem = try XCTUnwrap(plan.items.first { $0.entryPath == "root" })
        XCTAssertEqual(rootItem.size, 0)
        let file = try XCTUnwrap(plan.items.first { $0.entryPath == "root/a.txt" })
        XCTAssertEqual(file.size, 1)
    }

    func testSingleFileKeepsItsName() throws {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent("hello.txt")
        try TestSupport.write("hello", to: file)

        let plan = try CreationPlanner.plan(items: [file],
                                            cancelFlag: CancelFlag(),
                                            progress: { _ in })
        XCTAssertEqual(plan.items.map(\.entryPath), ["hello.txt"])
        XCTAssertEqual(plan.items.first?.size, 5)
    }

    func testDuplicateRootNamesAreDisambiguated() throws {
        let directory = try makeTemporaryDirectory()
        let first = directory.appendingPathComponent("one/data", isDirectory: true)
        let second = directory.appendingPathComponent("two/data", isDirectory: true)
        try TestSupport.write("a", to: first.appendingPathComponent("a.txt"))
        try TestSupport.write("b", to: second.appendingPathComponent("b.txt"))

        let plan = try CreationPlanner.plan(items: [first, second],
                                            cancelFlag: CancelFlag(),
                                            progress: { _ in })
        XCTAssertEqual(Set(plan.items.map(\.entryPath)), [
            "data", "data/a.txt", "data (2)", "data (2)/b.txt"
        ])
    }

    func testCancellationStopsPlanning() throws {
        let directory = try makeTemporaryDirectory()
        let root = directory.appendingPathComponent("root", isDirectory: true)
        try TestSupport.write("a", to: root.appendingPathComponent("a.txt"))

        let flag = CancelFlag()
        flag.cancel()
        XCTAssertThrowsError(try CreationPlanner.plan(items: [root],
                                                      cancelFlag: flag,
                                                      progress: { _ in })) { error in
            guard case ArchiveError.cancelled = error else {
                return XCTFail("expected cancellation, got \(error)")
            }
        }
    }

    func testFinalProgressReportsTotalCount() throws {
        let directory = try makeTemporaryDirectory()
        let root = directory.appendingPathComponent("root", isDirectory: true)
        try TestSupport.write("a", to: root.appendingPathComponent("a.txt"))

        final class Box: @unchecked Sendable {
            var found: Int?
        }
        let box = Box()
        let plan = try CreationPlanner.plan(items: [root],
                                            cancelFlag: CancelFlag(),
                                            progress: { phase in
            if case .scanning(let found, let path) = phase, path.isEmpty {
                box.found = found
            }
        })
        XCTAssertEqual(box.found, plan.items.count)
    }
}
