import Foundation

/// One row in the archive browser. Sort keys are precomputed so SwiftUI's table
/// can sort without touching archive state.
public struct ArchiveRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let packedSize: Int64?
    public let modified: Date?
    public let isEncrypted: Bool
    public let entryIndex: Int?
    public let sortName: String
    public let sortSize: Int64
    public let sortPacked: Int64
    public let sortRatio: Double
    public let sortModified: Date

    public init(path: String,
                name: String,
                isDirectory: Bool,
                size: Int64,
                packedSize: Int64?,
                modified: Date?,
                isEncrypted: Bool,
                entryIndex: Int?,
                locale: Locale = .current) {
        self.id = path
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.entryIndex = entryIndex
        self.sortName = name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: locale)
        self.sortSize = size
        self.sortPacked = packedSize ?? 0
        if let packedSize, size > 0 {
            self.sortRatio = 1 - (Double(packedSize) / Double(size))
        } else {
            self.sortRatio = -1
        }
        self.sortModified = modified ?? .distantPast
    }
}

/// Builds the rows shown for one folder, or across the whole archive while
/// searching. This is pure apart from Foundation's collation.
public enum ArchiveBrowser {
    public static func rows(in folder: String,
                            index: ArchiveIndex,
                            query: String = "",
                            sortOrder: [KeyPathComparator<ArchiveRow>] = [KeyPathComparator(\ArchiveRow.sortName)],
                            locale: Locale = .current) -> [ArchiveRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [ArchiveRow] = []
        var seen = Set<String>()

        if trimmed.isEmpty {
            for folderPath in index.children(of: folder).sorted() {
                appendUnique(folderRow(folderPath,
                                       displayName: ArchivePath.name(of: folderPath),
                                       index: index,
                                       locale: locale),
                             to: &result,
                             seen: &seen)
            }
            for entry in index.files(in: folder) {
                appendUnique(fileRow(entry, displayPath: entry.name, locale: locale),
                             to: &result,
                             seen: &seen)
            }
        } else {
            for entry in index.entries where entry.path.localizedCaseInsensitiveContains(trimmed) {
                let row = fileRow(entry, displayPath: entry.path, locale: locale)
                if entry.isDirectory {
                    appendUnique(ArchiveRow(path: row.path,
                                            name: row.name,
                                            isDirectory: true,
                                            size: index.folderSize(entry.path),
                                            packedSize: row.packedSize,
                                            modified: row.modified,
                                            isEncrypted: row.isEncrypted,
                                            entryIndex: row.entryIndex,
                                            locale: locale),
                                 to: &result,
                                 seen: &seen)
                } else {
                    appendUnique(row, to: &result, seen: &seen)
                }
            }

            for folderPath in index.allFolders.sorted()
            where index.explicitFolders[folderPath] == nil
                && folderPath.localizedCaseInsensitiveContains(trimmed) {
                appendUnique(folderRow(folderPath,
                                       displayName: folderPath,
                                       index: index,
                                       locale: locale),
                             to: &result,
                             seen: &seen)
            }
        }

        return result.sorted(using: sortOrder)
    }

    /// Archives can legally contain the same path more than once. SwiftUI's
    /// table requires stable unique identifiers, so keep the first row only.
    private static func appendUnique(_ row: ArchiveRow,
                                     to rows: inout [ArchiveRow],
                                     seen: inout Set<String>) {
        if seen.insert(row.id).inserted {
            rows.append(row)
        }
    }

    private static func folderRow(_ path: String,
                                  displayName: String,
                                  index: ArchiveIndex,
                                  locale: Locale) -> ArchiveRow {
        let entry = index.folderEntry(at: path)
        return ArchiveRow(path: path,
                          name: displayName,
                          isDirectory: true,
                          size: index.folderSize(path),
                          packedSize: nil,
                          modified: entry?.modified,
                          isEncrypted: false,
                          entryIndex: entry?.id,
                          locale: locale)
    }

    private static func fileRow(_ entry: ArchiveEntry,
                                displayPath: String,
                                locale: Locale) -> ArchiveRow {
        ArchiveRow(path: entry.path,
                   name: displayPath,
                   isDirectory: entry.isDirectory,
                   size: entry.size,
                   packedSize: entry.compressedSize,
                   modified: entry.modified,
                   isEncrypted: entry.isEncrypted,
                   entryIndex: entry.id,
                   locale: locale)
    }
}
