import Foundation
import XCTest
@testable import UnzipperCore

enum TestSupport {
    static func entry(id: Int,
                      path: String,
                      isDirectory: Bool = false,
                      size: Int64 = 0,
                      packed: Int64? = nil,
                      modified: Date? = nil,
                      encrypted: Bool = false) -> ArchiveEntry {
        ArchiveEntry(id: id,
                     path: path,
                     name: ArchivePath.name(of: path),
                     parent: ArchivePath.parent(of: path),
                     isDirectory: isDirectory,
                     size: size,
                     compressedSize: packed,
                     modified: modified,
                     isEncrypted: encrypted,
                     mode: isDirectory ? 0o40755 : 0o100644,
                     symlinkTarget: nil)
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Builds a valid ZIP using the stored (uncompressed) method. Useful for
    /// fixtures that `zip(1)` cannot easily produce, such as `../` entry names.
    static func zip(_ entries: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            output.le(UInt32(0x04034B50))
            output.le(UInt16(20))          // version needed
            output.le(UInt16(0x0800))      // UTF-8 names
            output.le(UInt16(0))           // stored
            output.le(UInt16(0))           // time
            output.le(UInt16(0))           // date
            output.le(crc)
            output.le(UInt32(entry.data.count))
            output.le(UInt32(entry.data.count))
            output.le(UInt16(name.count))
            output.le(UInt16(0))           // extra length
            output.append(name)
            output.append(entry.data)

            central.le(UInt32(0x02014B50))
            central.le(UInt16(20))         // version made by
            central.le(UInt16(20))         // version needed
            central.le(UInt16(0x0800))
            central.le(UInt16(0))
            central.le(UInt16(0))
            central.le(UInt16(0))
            central.le(crc)
            central.le(UInt32(entry.data.count))
            central.le(UInt32(entry.data.count))
            central.le(UInt16(name.count))
            central.le(UInt16(0))          // extra
            central.le(UInt16(0))          // comment
            central.le(UInt16(0))          // disk
            central.le(UInt16(0))          // internal attributes
            central.le(UInt32(0))          // external attributes
            central.le(offset)
            central.append(name)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.le(UInt32(0x06054B50))
        output.le(UInt16(0))               // disk
        output.le(UInt16(0))               // central directory disk
        output.le(UInt16(entries.count))
        output.le(UInt16(entries.count))
        output.le(UInt32(central.count))
        output.le(centralOffset)
        output.le(UInt16(0))               // comment length
        return output
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? 0xEDB88320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnzipperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
