import CoreFoundation
import Foundation

struct PlannedItem: Sendable {
    let diskURL: URL
    let entryPath: String
    let size: Int64
}

struct CreationPlan: Sendable {
    let items: [PlannedItem]
}

enum CreationPlanner {
    static func plan(items: [URL],
                     cancelFlag: CancelFlag,
                     progress: @escaping @Sendable (CreationPhase) -> Void) throws -> CreationPlan {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]
        var planned: [PlannedItem] = []
        var seenEntries = Set<String>()
        var usedRootNames = Set<String>()
        var emittedAt = CFAbsoluteTimeGetCurrent()

        func emit(found: Int, path: String) {
            let now = CFAbsoluteTimeGetCurrent()
            if now - emittedAt >= 0.08 {
                emittedAt = now
                progress(.scanning(found: found, currentPath: path))
            }
        }

        func add(_ url: URL, entryPath: String, isDirectory: Bool, size: Int64) {
            guard !seenEntries.contains(entryPath) else { return }
            seenEntries.insert(entryPath)
            planned.append(PlannedItem(diskURL: url, entryPath: entryPath, size: isDirectory ? 0 : size))
        }

        for root in items {
            if cancelFlag.isCancelled { throw ArchiveError.cancelled }

            var baseName = root.lastPathComponent
            if baseName.isEmpty { baseName = "Item" }
            if usedRootNames.contains(baseName) {
                var suffix = 2
                while usedRootNames.contains("\(baseName) (\(suffix))") { suffix += 1 }
                baseName = "\(baseName) (\(suffix))"
            }
            usedRootNames.insert(baseName)

            let rootValues = try? root.resourceValues(forKeys: keys)
            let rootIsSymlink = rootValues?.isSymbolicLink ?? false
            let rootIsDirectory = (rootValues?.isDirectory ?? false) && !rootIsSymlink
            let rootSize = Int64(rootValues?.fileSize ?? 0)

            add(root, entryPath: baseName, isDirectory: rootIsDirectory, size: rootSize)
            emit(found: planned.count, path: baseName)

            guard rootIsDirectory else { continue }

            let enumerator = FileManager.default.enumerator(at: root,
                                                            includingPropertiesForKeys: Array(keys),
                                                            options: [],
                                                            errorHandler: { _, _ in true })
            var relativePrefix = ""
            if let enumerator {
                for case let child as URL in enumerator {
                    if cancelFlag.isCancelled { throw ArchiveError.cancelled }

                    let relative = relativePath(of: child, under: root)
                    guard !relative.isEmpty else { continue }
                    let childValues = try? child.resourceValues(forKeys: keys)
                    let isSymlink = childValues?.isSymbolicLink ?? false
                    let isDirectory = (childValues?.isDirectory ?? false) && !isSymlink
                    let size = Int64(childValues?.fileSize ?? 0)
                    let entryPath = baseName + "/" + relative
                    add(child, entryPath: entryPath, isDirectory: isDirectory, size: size)
                    relativePrefix = relative
                    emit(found: planned.count, path: relativePrefix)
                }
            }
        }

        progress(.scanning(found: planned.count, currentPath: ""))
        return CreationPlan(items: planned)
    }

    private static func relativePath(of child: URL, under root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            return child.lastPathComponent
        }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
