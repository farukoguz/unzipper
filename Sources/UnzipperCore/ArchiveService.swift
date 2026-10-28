import CSArchive
import Darwin
import Foundation

public struct ExtractionRequest: Sendable {
    public let archiveURL: URL
    public let destination: URL
    public let entryIndices: [Int]
    public let totalEntries: Int
    public let password: String?
    public let overwrite: Bool
    public let totalBytes: Int64

    public init(archiveURL: URL,
                destination: URL,
                entryIndices: [Int],
                totalEntries: Int,
                password: String?,
                overwrite: Bool,
                totalBytes: Int64) {
        self.archiveURL = archiveURL
        self.destination = destination
        self.entryIndices = entryIndices
        self.totalEntries = totalEntries
        self.password = password
        self.overwrite = overwrite
        self.totalBytes = totalBytes
    }
}

public struct CreationRequest: Sendable {
    public let destination: URL
    public let items: [URL]
    public let format: ArchiveFormat
    public let compressionLevel: Int

    public init(destination: URL,
                items: [URL],
                format: ArchiveFormat,
                compressionLevel: Int) {
        self.destination = destination
        self.items = items
        self.format = format
        self.compressionLevel = compressionLevel
    }
}

public enum ArchiveService {
    // MARK: - Listing

    public static func list(url: URL) async throws -> ArchiveListing {
        try await Task.detached(priority: .userInitiated) {
            try listSync(url)
        }.value
    }

    static func listSync(_ url: URL) throws -> ArchiveListing {
        var rawEntries: UnsafeMutablePointer<UZEntry>?
        var count: Int32 = 0
        var formatPtr: UnsafeMutablePointer<CChar>?
        var filterPtr: UnsafeMutablePointer<CChar>?
        var errorPtr: UnsafeMutablePointer<CChar>?

        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(UZ_ERR) }
            return uz_list(path, &rawEntries, &count, &formatPtr, &filterPtr, &errorPtr)
        }

        defer {
            uz_free_entries(rawEntries, count)
            if let formatPtr { uz_free_string(formatPtr) }
            if let filterPtr { uz_free_string(filterPtr) }
        }

        if result != Int32(UZ_OK) {
            throw ArchiveError.message(takeError(errorPtr) ?? "The archive could not be opened.")
        }
        _ = takeError(errorPtr)

        let formatName = formatPtr.map { String(cString: $0) } ?? "Archive"
        let filterName = filterPtr.map { String(cString: $0) } ?? "none"
        let packedSizes = ZipMetadata.isZipFile(url) ? ZipMetadata.compressedSizes(at: url) : [:]

        var entries: [ArchiveEntry] = []
        entries.reserveCapacity(Int(count))
        if let rawEntries {
            let buffer = UnsafeBufferPointer(start: rawEntries, count: Int(count))
            for (index, raw) in buffer.enumerated() {
                guard let rawPath = raw.pathname else { continue }
                let path = String(cString: rawPath)
                if path.isEmpty { continue }

                let pieces = path.split(separator: "/", omittingEmptySubsequences: true)
                let name = pieces.last.map(String.init) ?? path
                let parent = pieces.dropLast().joined(separator: "/")
                let modified = raw.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(raw.mtime)) : nil
                let symlink = raw.symlink.map { String(cString: $0) }
                let packed = packedSizes[path]

                entries.append(ArchiveEntry(id: index,
                                            path: path,
                                            name: name,
                                            parent: parent,
                                            isDirectory: raw.is_dir != 0,
                                            size: max(0, raw.size),
                                            compressedSize: packed,
                                            modified: modified,
                                            isEncrypted: raw.is_encrypted != 0,
                                            mode: raw.mode,
                                            symlinkTarget: symlink))
            }
        }

        let files = entries.filter { !$0.isDirectory }
        let totalSize = files.reduce(Int64(0)) { $0 + $1.size }
        let totalCompressed: Int64? = {
            guard !packedSizes.isEmpty, !files.isEmpty else { return nil }
            var sum: Int64 = 0
            for file in files {
                guard let packed = file.compressedSize else { return nil }
                sum += packed
            }
            return sum
        }()

        return ArchiveListing(url: url,
                              entries: entries,
                              formatName: formatName,
                              filterName: filterName,
                              totalSize: totalSize,
                              totalCompressed: totalCompressed,
                              containsEncryptedEntries: entries.contains { $0.isEncrypted })
    }

    // MARK: - Extraction

    public static func extract(_ request: ExtractionRequest,
                               cancelFlag: CancelFlag,
                               progress: @escaping @Sendable (ProgressUpdate) -> Void) async throws {
        try await Task.detached(priority: .userInitiated) {
            try extractSync(request, cancelFlag: cancelFlag, progress: progress)
        }.value
    }

    private static func extractSync(_ request: ExtractionRequest,
                                    cancelFlag: CancelFlag,
                                    progress: @escaping @Sendable (ProgressUpdate) -> Void) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: request.destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ArchiveError.message("The destination is not a folder.")
            }
        } else {
            do {
                try fileManager.createDirectory(at: request.destination, withIntermediateDirectories: true)
            } catch {
                throw ArchiveError.message("Could not create the destination folder: \(error.localizedDescription)")
            }
        }

        let relay = ProgressRelay(cancelFlag: cancelFlag, handler: progress)
        let indices = request.entryIndices.sorted().map(Int32.init)
        var errorPtr: UnsafeMutablePointer<CChar>?
        var rc: Int32 = Int32(UZ_ERR)

        rc = request.archiveURL.withUnsafeFileSystemRepresentation { archivePath in
            guard let archivePath else { return Int32(UZ_ERR) }
            return request.destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { return Int32(UZ_ERR) }
                return indices.withUnsafeBufferPointer { buffer in
                    let cProgress = makeCProgress(relay)
                    if let password = request.password, !password.isEmpty {
                        return password.withCString { passwordPtr in
                            uz_extract(archivePath,
                                       destinationPath,
                                       buffer.baseAddress,
                                       Int32(buffer.count),
                                       Int32(request.totalEntries),
                                       passwordPtr,
                                       request.overwrite ? 1 : 0,
                                       request.totalBytes,
                                       cProgress,
                                       &errorPtr)
                        }
                    }
                    return uz_extract(archivePath,
                                      destinationPath,
                                      buffer.baseAddress,
                                      Int32(buffer.count),
                                      Int32(request.totalEntries),
                                      nil,
                                      request.overwrite ? 1 : 0,
                                      request.totalBytes,
                                      cProgress,
                                      &errorPtr)
                }
            }
        }

        let errorMessage = takeError(errorPtr)
        if rc == Int32(UZ_ERR_CANCELLED) {
            throw ArchiveError.cancelled
        }
        if rc != Int32(UZ_OK) {
            throw ArchiveError.message(errorMessage ?? "Extraction failed.")
        }
    }

    // MARK: - Creation

    public static func create(_ request: CreationRequest,
                              cancelFlag: CancelFlag,
                              progress: @escaping @Sendable (CreationPhase) -> Void) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try createSync(request, cancelFlag: cancelFlag, progress: progress)
        }.value
    }

    private static func createSync(_ request: CreationRequest,
                                   cancelFlag: CancelFlag,
                                   progress: @escaping @Sendable (CreationPhase) -> Void) throws -> URL {
        guard !request.items.isEmpty else {
            throw ArchiveError.message("There are no files to add.")
        }

        let planned = try CreationPlanner.plan(items: request.items,
                                               cancelFlag: cancelFlag,
                                               progress: progress)
        if cancelFlag.isCancelled { throw ArchiveError.cancelled }
        guard !planned.items.isEmpty else {
            throw ArchiveError.message("There are no files to add.")
        }

        let totalBytes = planned.items.reduce(Int64(0)) { $0 + $1.size }
        let relay = ProgressRelay(cancelFlag: cancelFlag) { update in
            progress(.writing(update))
        }

        var errorPtr: UnsafeMutablePointer<CChar>?
        let cProgress = makeCProgress(relay)

        // Build into a sibling temporary file and rename it into place only
        // after the archive has been finalized. Opening the destination
        // directly would truncate an existing archive before the user's
        // cancelled or failed attempt had a chance to preserve it.
        let fileManager = FileManager.default
        let destination = request.destination
        let temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        func discardTemporaryArchive() {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let writer: OpaquePointer? = temporaryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return uz_writer_open(path,
                                  request.format.identifier,
                                  Int32(request.compressionLevel),
                                  totalBytes,
                                  Int32(planned.items.count),
                                  cProgress,
                                  &errorPtr)
        }

        guard let writer else {
            let message = takeError(errorPtr) ?? "Could not create the archive."
            discardTemporaryArchive()
            throw ArchiveError.message(message)
        }
        _ = takeError(errorPtr)

        var failed = false
        for item in planned.items {
            if cancelFlag.isCancelled {
                uz_writer_abort(writer)
                discardTemporaryArchive()
                throw ArchiveError.cancelled
            }
            let rc: Int32 = item.diskURL.withUnsafeFileSystemRepresentation { diskPath in
                guard let diskPath else { return Int32(UZ_ERR) }
                return item.entryPath.withCString { entryPath in
                    uz_writer_add(writer, diskPath, entryPath, &errorPtr)
                }
            }
            if rc == Int32(UZ_ERR_CANCELLED) {
                uz_writer_abort(writer)
                discardTemporaryArchive()
                throw ArchiveError.cancelled
            }
            if rc != Int32(UZ_OK) {
                failed = true
                break
            }
        }

        let addError = takeError(errorPtr)
        if failed {
            uz_writer_abort(writer)
            discardTemporaryArchive()
            throw ArchiveError.message(addError ?? "Could not add a file to the archive.")
        }

        if uz_writer_close(writer, &errorPtr) != Int32(UZ_OK) {
            let closeError = takeError(errorPtr)
            discardTemporaryArchive()
            throw ArchiveError.message(closeError ?? "Could not finish the archive.")
        }
        _ = takeError(errorPtr)

        let renameError: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            guard let temporaryPath else { return Int32(EINVAL) }
            return destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { return Int32(EINVAL) }
                if rename(temporaryPath, destinationPath) == 0 { return 0 }
                return Int32(errno)
            }
        }
        if renameError != 0 {
            let message = String(cString: strerror(renameError))
            discardTemporaryArchive()
            throw ArchiveError.message("Could not save the archive: \(message)")
        }

        return destination
    }
}
