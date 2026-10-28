import Foundation

/// Immutable folder/file index over an archive listing.
///
/// Archives are not required to contain directory entries, so every folder chain
/// implied by an entry path is materialised here. The index keeps the browsing
/// layer free of repeated whole-listing scans.
public struct ArchiveIndex: Sendable {
    public let entries: [ArchiveEntry]
    public let entryByID: [Int: ArchiveEntry]
    public let folderChildren: [String: Set<String>]
    /// Every folder path in the archive, explicit or implied by a file path.
    public let allFolders: Set<String>
    public let filesByParent: [String: [ArchiveEntry]]
    public let folderSizes: [String: Int64]
    public let folderFileCounts: [String: Int]
    public let explicitFolders: [String: ArchiveEntry]
    public let totalFileCount: Int

    public init(entries: [ArchiveEntry]) {
        self.entries = entries
        self.entryByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.totalFileCount = entries.reduce(0) { $0 + ($1.isDirectory ? 0 : 1) }

        var folderChildren: [String: Set<String>] = [:]
        var allFolders: Set<String> = []
        var filesByParent: [String: [ArchiveEntry]] = [:]
        var folderSizes: [String: Int64] = [:]
        var folderFileCounts: [String: Int] = [:]
        var explicitFolders: [String: ArchiveEntry] = [:]

        for entry in entries {
            // Materialise every folder implied by the entry path.
            var parent = ""
            let pieces = ArchivePath.components(of: entry.path)
            if pieces.count > 1 {
                for piece in pieces.dropLast() {
                    let child = parent.isEmpty ? piece : parent + "/" + piece
                    folderChildren[parent, default: []].insert(child)
                    allFolders.insert(child)
                    parent = child
                }
            }

            if entry.isDirectory {
                explicitFolders[entry.path] = entry
                folderChildren[entry.parent, default: []].insert(entry.path)
                allFolders.insert(entry.path)
            }

            for ancestor in ArchivePath.ancestors(of: entry.path) {
                folderSizes[ancestor, default: 0] += entry.size
                if !entry.isDirectory {
                    folderFileCounts[ancestor, default: 0] += 1
                }
            }

            if !entry.isDirectory {
                filesByParent[entry.parent, default: []].append(entry)
            }
        }

        self.folderChildren = folderChildren
        self.allFolders = allFolders
        self.filesByParent = filesByParent
        self.folderSizes = folderSizes
        self.folderFileCounts = folderFileCounts
        self.explicitFolders = explicitFolders
    }

    public func entry(withID id: Int) -> ArchiveEntry? {
        entryByID[id]
    }

    /// Immediate child folder paths (not just names) of a folder.
    public func children(of folder: String) -> Set<String> {
        folderChildren[folder] ?? []
    }

    public func files(in folder: String) -> [ArchiveEntry] {
        filesByParent[folder] ?? []
    }

    public func folderSize(_ folder: String) -> Int64 {
        folderSizes[folder] ?? 0
    }

    public func fileCount(inFolder folder: String) -> Int {
        folderFileCounts[folder] ?? 0
    }

    public func folderEntry(at path: String) -> ArchiveEntry? {
        explicitFolders[path]
    }

    /// Every ordinal needed to extract the given rows. Folder rows expand to their
    /// own directory entry (when present) plus every descendant.
    public func indices(for rows: [ArchiveRow]) -> [Int] {
        var result = Set<Int>()
        for row in rows {
            if row.isDirectory {
                result.formUnion(indices(inFolder: row.path))
            } else if let entryIndex = row.entryIndex {
                result.insert(entryIndex)
            }
        }
        return result.sorted()
    }

    public func indices(inFolder path: String) -> [Int] {
        let prefix = path.isEmpty ? "" : path + "/"
        return entries.lazy
            .filter { entry in
                if path.isEmpty { return true }
                return entry.path == path || entry.path.hasPrefix(prefix)
            }
            .map(\.id)
            .sorted()
    }
}
