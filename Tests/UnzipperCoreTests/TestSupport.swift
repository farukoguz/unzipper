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

    /// Builds a literal-only LZ4 block. The resulting block is valid for both
    /// independent and linked frames.
    static func lz4LiteralBlock(_ data: Data) -> Data {
        var block = Data()
        if data.count < 15 {
            block.append(UInt8(data.count << 4))
        } else {
            block.append(0xF0)
            var remaining = data.count - 15
            while remaining >= 255 {
                block.append(255)
                remaining -= 255
            }
            block.append(UInt8(remaining))
        }
        block.append(data)
        return block
    }

    /// Wraps already-encoded blocks in an LZ4 frame. The header always carries
    /// the content size; checksums are optional so tests can cover both paths.
    static func lz4Frame(rawBlocks: [Data],
                         content: Data,
                         linked: Bool = false,
                         blockChecksums: Bool = true,
                         contentChecksum: Bool = true) -> Data {
        var output = Data()
        output.le(UInt32(0x184D2204))

        var flags: UInt8 = 0x40          // version 1
        if !linked { flags |= 0x20 }     // independent blocks
        if blockChecksums { flags |= 0x10 }
        flags |= 0x08                    // content size present
        if contentChecksum { flags |= 0x04 }

        let blockDescriptor: UInt8 = 0x70 // 4 MB blocks
        var descriptor = Data([flags, blockDescriptor])
        descriptor.le(UInt64(content.count))
        output.append(descriptor)
        output.append(UInt8((xxh32(descriptor) >> 8) & 0xFF))

        for block in rawBlocks {
            output.le(UInt32(block.count))
            output.append(block)
            if blockChecksums { output.le(xxh32(block)) }
        }
        output.le(UInt32(0))
        if contentChecksum { output.le(xxh32(content)) }
        return output
    }

    /// xxHash32 as used by the LZ4 frame format.
    private static func xxh32(_ data: Data) -> UInt32 {
        let bytes = [UInt8](data)
        let prime1: UInt32 = 0x9E3779B1
        let prime2: UInt32 = 0x85EBCA77
        let prime3: UInt32 = 0xC2B2AE3D
        let prime4: UInt32 = 0x27D4EB2F
        let prime5: UInt32 = 0x165667B1
        var index = 0
        var hash: UInt32

        if bytes.count >= 16 {
            var v1 = prime1 &+ prime2
            var v2 = prime2
            var v3: UInt32 = 0
            var v4: UInt32 = 0 &- prime1
            while index <= bytes.count - 16 {
                v1 = rotate(v1 &+ readLE32(bytes, index) &* prime2, 13) &* prime1
                index += 4
                v2 = rotate(v2 &+ readLE32(bytes, index) &* prime2, 13) &* prime1
                index += 4
                v3 = rotate(v3 &+ readLE32(bytes, index) &* prime2, 13) &* prime1
                index += 4
                v4 = rotate(v4 &+ readLE32(bytes, index) &* prime2, 13) &* prime1
                index += 4
            }
            hash = rotate(v1, 1) &+ rotate(v2, 7) &+ rotate(v3, 12) &+ rotate(v4, 18)
        } else {
            hash = prime5
        }

        hash = hash &+ UInt32(bytes.count)
        while index <= bytes.count - 4 {
            hash = hash &+ readLE32(bytes, index) &* prime3
            hash = rotate(hash, 17) &* prime4
            index += 4
        }
        while index < bytes.count {
            hash = hash &+ UInt32(bytes[index]) &* prime5
            hash = rotate(hash, 11) &* prime1
            index += 1
        }

        hash ^= hash >> 15
        hash = hash &* prime2
        hash ^= hash >> 13
        hash = hash &* prime3
        hash ^= hash >> 16
        return hash
    }

    private static func readLE32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) |
        (UInt32(bytes[index + 1]) << 8) |
        (UInt32(bytes[index + 2]) << 16) |
        (UInt32(bytes[index + 3]) << 24)
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
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
