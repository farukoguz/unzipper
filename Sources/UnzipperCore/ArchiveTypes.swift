import Foundation

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    public let path: String
    public let name: String
    public let parent: String
    public let isDirectory: Bool
    public let size: Int64
    public let compressedSize: Int64?
    public let modified: Date?
    public let isEncrypted: Bool
    public let mode: UInt32
    public let symlinkTarget: String?

    public init(id: Int,
                path: String,
                name: String,
                parent: String,
                isDirectory: Bool,
                size: Int64,
                compressedSize: Int64?,
                modified: Date?,
                isEncrypted: Bool,
                mode: UInt32,
                symlinkTarget: String?) {
        self.id = id
        self.path = path
        self.name = name
        self.parent = parent
        self.isDirectory = isDirectory
        self.size = size
        self.compressedSize = compressedSize
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.mode = mode
        self.symlinkTarget = symlinkTarget
    }

    public var ratio: Double? {
        guard let packed = compressedSize, size > 0, packed > 0 else { return nil }
        return Double(packed) / Double(size)
    }
}

public struct ArchiveListing: Sendable {
    public let url: URL
    public let entries: [ArchiveEntry]
    public let formatName: String
    public let filterName: String
    public let totalSize: Int64
    public let totalCompressed: Int64?
    public let containsEncryptedEntries: Bool

    public init(url: URL,
                entries: [ArchiveEntry],
                formatName: String,
                filterName: String,
                totalSize: Int64,
                totalCompressed: Int64?,
                containsEncryptedEntries: Bool) {
        self.url = url
        self.entries = entries
        self.formatName = formatName
        self.filterName = filterName
        self.totalSize = totalSize
        self.totalCompressed = totalCompressed
        self.containsEncryptedEntries = containsEncryptedEntries
    }

    public var displayFormat: String {
        var parts: [String] = [formatName]
        if !filterName.isEmpty, filterName.lowercased() != "none" {
            parts.append(filterName.uppercased())
        }
        return parts.joined(separator: " · ")
    }
}

public struct ProgressUpdate: Sendable {
    public let currentPath: String
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let entriesDone: Int
    public let entriesTotal: Int

    public init(currentPath: String,
                completedBytes: Int64,
                totalBytes: Int64,
                entriesDone: Int,
                entriesTotal: Int) {
        self.currentPath = currentPath
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.entriesDone = entriesDone
        self.entriesTotal = entriesTotal
    }

    public var fraction: Double {
        if totalBytes > 0 { return min(1, max(0, Double(completedBytes) / Double(totalBytes))) }
        if entriesTotal > 0 { return min(1, max(0, Double(entriesDone) / Double(entriesTotal))) }
        return 0
    }
}

public enum CreationPhase: Sendable {
    case scanning(found: Int, currentPath: String)
    case writing(ProgressUpdate)
}

public enum ArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip
    case tarGz

    public var identifier: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tarGz: return "tar.gz"
        }
    }

    public var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tarGz: return "TAR.GZ"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tarGz: return "tar.gz"
        }
    }
}

public enum ArchiveError: LocalizedError {
    case cancelled
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "The operation was cancelled."
        case .message(let text): return text
        }
    }
}

public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    public init() {}

    public func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
