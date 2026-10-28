import Foundation
import UnzipperCore

func run() async throws {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write("usage: CoreTest list|extract|create ...\n".data(using: .utf8)!)
        exit(2)
    }

    switch args[1] {
    case "list":
        guard args.count >= 3 else { exit(2) }
        let listing = try await ArchiveService.list(url: URL(fileURLWithPath: args[2]))
        print("format=\(listing.displayFormat) entries=\(listing.entries.count) size=\(listing.totalSize) packed=\(listing.totalCompressed.map(String.init) ?? "-")")
        for entry in listing.entries {
            print(String(format: "%4d %@ %10lld %@%@",
                         entry.id,
                         entry.isDirectory ? "d" : "-",
                         entry.size,
                         entry.path,
                         entry.isEncrypted ? " [encrypted]" : ""))
        }

    case "extract":
        guard args.count >= 4 else { exit(2) }
        let url = URL(fileURLWithPath: args[2])
        let destination = URL(fileURLWithPath: args[3])
        let listing = try await ArchiveService.list(url: url)
        let request = ExtractionRequest(archiveURL: url,
                                        destination: destination,
                                        entryIndices: listing.entries.map(\.id),
                                        totalEntries: listing.entries.count,
                                        password: args.count > 4 ? args[4] : nil,
                                        overwrite: true,
                                        totalBytes: listing.totalSize)
        let flag = CancelFlag()
        try await ArchiveService.extract(request, cancelFlag: flag) { update in
            print(String(format: "  %3d%% %@", Int(update.fraction * 100), update.currentPath))
        }
        print("extracted OK")

    case "create":
        guard args.count >= 5 else { exit(2) }
        let destination = URL(fileURLWithPath: args[2])
        let format: ArchiveFormat
        switch args[3] {
        case "zip": format = .zip
        case "7z": format = .sevenZip
        case "tar.gz": format = .tarGz
        default: exit(2)
        }
        let items = args.dropFirst(4).map { URL(fileURLWithPath: $0) }
        let request = CreationRequest(destination: destination,
                                      items: Array(items),
                                      format: format,
                                      compressionLevel: 6)
        let flag = CancelFlag()
        let result = try await ArchiveService.create(request, cancelFlag: flag) { phase in
            switch phase {
            case .scanning(let found, let path):
                print("  scanning \(found) \(path)")
            case .writing(let update):
                print(String(format: "  %3d%% %@", Int(update.fraction * 100), update.currentPath))
            }
        }
        print("created \(result.path)")

    default:
        exit(2)
    }
}

Task {
    do {
        try await run()
        exit(0)
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

RunLoop.main.run()
