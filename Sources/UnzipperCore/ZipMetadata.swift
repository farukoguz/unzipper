import CSArchive
import Foundation

/// Reads the ZIP central directory to recover per-entry packed sizes.
/// Listing itself goes through libarchive so entry order stays identical
/// between browsing and extraction.
enum ZipMetadata {
    private static let cp437Scalars: [UnicodeScalar] = Array(
        "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{00A0}"
            .unicodeScalars
    )

    static func isZipFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic.count == 4 else { return false }
        let bytes = [UInt8](magic)
        guard bytes[0] == 0x50, bytes[1] == 0x4B else { return false }
        return (bytes[2] == 0x03 && (bytes[3] == 0x04 || bytes[3] == 0x06)) ||
               (bytes[2] == 0x05 && bytes[3] == 0x06) ||
               (bytes[2] == 0x06 && bytes[3] == 0x06) ||
               (bytes[2] == 0x07 && bytes[3] == 0x08)
    }

    static func compressedSizes(at url: URL) -> [String: Int64] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize >= 22 else { return [:] }
            let tailLength = Int(min(fileSize, 66_000))
            let tail = try read(handle, offset: fileSize - UInt64(tailLength), length: tailLength)
            guard tail.count >= 22 else { return [:] }

            guard let eocdIndex = findEOCD(in: tail) else { return [:] }
            let eocdAbsolute = fileSize - UInt64(tail.count) + UInt64(eocdIndex)

            var totalEntries = Int(u16(tail, eocdIndex + 10) ?? 0)
            var directorySize = Int64(u32(tail, eocdIndex + 12) ?? 0)
            var directoryOffset = Int64(u32(tail, eocdIndex + 16) ?? 0)

            let needsZip64 = totalEntries == 0xFFFF ||
                             directorySize == 0xFFFF_FFFF ||
                             directoryOffset == 0xFFFF_FFFF ||
                             (u16(tail, eocdIndex + 8) ?? 0) == 0xFFFF

            if needsZip64 {
                guard eocdAbsolute >= 20 else { return [:] }
                let locator = try read(handle, offset: eocdAbsolute - 20, length: 20)
                guard u32(locator, 0) == 0x07064B50,
                      let zip64Offset = u64(locator, 8) else { return [:] }
                let record = try read(handle, offset: zip64Offset, length: 56)
                guard u32(record, 0) == 0x06064B50,
                      let entries64 = u64(record, 32),
                      let size64 = u64(record, 40),
                      let offset64 = u64(record, 48) else { return [:] }
                guard entries64 <= UInt64(Int.max), size64 <= UInt64(Int.max), offset64 <= UInt64(Int64.max) else { return [:] }
                totalEntries = Int(entries64)
                directorySize = Int64(size64)
                directoryOffset = Int64(offset64)
            }

            guard directorySize >= 0, directoryOffset >= 0 else { return [:] }
            guard directorySize <= 512 * 1024 * 1024 else { return [:] }
            guard UInt64(directoryOffset) + UInt64(directorySize) <= fileSize else { return [:] }
            if totalEntries == 0 || directorySize == 0 { return [:] }

            let directory = try read(handle, offset: UInt64(directoryOffset), length: Int(directorySize))
            return parseCentralDirectory(directory, expectedCount: totalEntries)
        } catch {
            return [:]
        }
    }

    private static func findEOCD(in tail: Data) -> Int? {
        guard tail.count >= 22 else { return nil }
        var index = tail.count - 22
        while index >= 0 {
            if u32(tail, index) == 0x06054B50 {
                let commentLength = Int(u16(tail, index + 20) ?? 0)
                if index + 22 + commentLength <= tail.count {
                    return index
                }
            }
            index -= 1
        }
        return nil
    }

    private static func parseCentralDirectory(_ data: Data, expectedCount: Int) -> [String: Int64] {
        var result: [String: Int64] = [:]
        result.reserveCapacity(expectedCount)
        var offset = 0
        var parsed = 0

        while parsed < expectedCount, offset + 46 <= data.count {
            guard u32(data, offset) == 0x02014B50,
                  let flags = u16(data, offset + 8),
                  let compressed32 = u32(data, offset + 20),
                  let uncompressed32 = u32(data, offset + 24),
                  let nameLength = u16(data, offset + 28),
                  let extraLength = u16(data, offset + 30),
                  let commentLength = u16(data, offset + 32) else { break }

            let nameStart = offset + 46
            let extraStart = nameStart + Int(nameLength)
            let extraEnd = extraStart + Int(extraLength)
            let entryEnd = extraEnd + Int(commentLength)
            guard extraEnd <= data.count, entryEnd <= data.count else { break }

            let nameData = data.subdata(in: nameStart..<extraStart)
            var compressed = Int64(compressed32)
            var unicodeName: String?

            var cursor = extraStart
            while cursor + 4 <= extraEnd {
                guard let tag = u16(data, cursor),
                      let length = u16(data, cursor + 2) else { break }
                let valueStart = cursor + 4
                let valueEnd = valueStart + Int(length)
                guard valueEnd <= extraEnd else { break }

                if tag == 0x0001 {
                    var valueCursor = valueStart
                    if uncompressed32 == 0xFFFF_FFFF, valueCursor + 8 <= valueEnd,
                       u64(data, valueCursor) != nil {
                        valueCursor += 8
                    }
                    if compressed32 == 0xFFFF_FFFF, valueCursor + 8 <= valueEnd,
                       let value = u64(data, valueCursor) {
                        compressed = Int64(bitPattern: value)
                        valueCursor += 8
                    }
                } else if tag == 0x7075, length > 5 {
                    let version = data[valueStart]
                    if version == 1 {
                        let unicodeData = data.subdata(in: (valueStart + 5)..<valueEnd)
                        if let decoded = String(data: unicodeData, encoding: .utf8) {
                            unicodeName = decoded
                        }
                    }
                }

                cursor = valueEnd
            }

            let name = unicodeName ?? decodeName(nameData, flags: flags)
            if !name.isEmpty, compressed >= 0 {
                var normalized: String?
                name.withCString { raw in
                    if let pointer = uz_normalize_path(raw) {
                        normalized = String(cString: pointer)
                        uz_free_string(pointer)
                    }
                }
                if let normalized, !normalized.isEmpty, result[normalized] == nil {
                    result[normalized] = compressed
                }
            }

            offset = entryEnd
            parsed += 1
        }

        return result
    }

    private static func decodeName(_ data: Data, flags: UInt16) -> String {
        if flags & 0x0800 != 0, let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        var scalars = String.UnicodeScalarView()
        for byte in data {
            if byte < 0x80 {
                scalars.append(UnicodeScalar(byte))
            } else {
                scalars.append(cp437Scalars[Int(byte) - 0x80])
            }
        }
        return String(scalars)
    }

    private static func read(_ handle: FileHandle, offset: UInt64, length: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: length) else {
            throw ArchiveError.message("Could not read the archive directory.")
        }
        return data
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }

    private static func u64(_ data: Data, _ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }.littleEndian
    }
}
