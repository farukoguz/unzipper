import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UnzipperCore

struct BrowserRow: Identifiable, Hashable {
    let id: String
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let packedSize: Int64?
    let modified: Date?
    let isEncrypted: Bool
    let entryIndex: Int?
    let sortName: String
    let sortSize: Int64
    let sortPacked: Int64
    let sortRatio: Double
    let sortModified: Date

    init(path: String,
         name: String,
         isDirectory: Bool,
         size: Int64,
         packedSize: Int64?,
         modified: Date?,
         isEncrypted: Bool,
         entryIndex: Int?) {
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
                                     locale: .current)
        self.sortSize = size
        self.sortPacked = packedSize ?? 0
        self.sortRatio = (packedSize != nil && size > 0) ? 1 - (Double(packedSize!) / Double(size)) : -1
        self.sortModified = modified ?? .distantPast
    }
}

struct ExtractSheetContext: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let archiveName: String
    let indices: [Int]
    let totalEntries: Int
    let totalBytes: Int64
    let containsEncrypted: Bool
    let selectionLabel: String
}

struct CreateSheetContext: Identifiable {
    let id = UUID()
    let items: [URL]
}

struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String
    let tempDirectory: URL
}

enum FileIcons {
    private static let folder = NSWorkspace.shared.icon(for: .folder)
    private static let generic = NSWorkspace.shared.icon(for: .data)
    private static var cache: [String: NSImage] = [:]

    static func icon(name: String, isDirectory: Bool) -> NSImage {
        if isDirectory { return folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return generic }
        if let cached = cache[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }

    static func archiveIcon() -> NSImage {
        NSWorkspace.shared.icon(for: .zip)
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var archiveURL: URL?
    @Published private(set) var listing: ArchiveListing?
    @Published private(set) var rows: [BrowserRow] = []
    @Published private(set) var currentPath = ""
    @Published private(set) var isLoading = false
    @Published var selection = Set<String>()
    @Published var searchText = "" { didSet { if searchText != oldValue { selection.removeAll(); rebuildRows() } } }
    @Published var sortOrder: [KeyPathComparator<BrowserRow>] = [KeyPathComparator(\BrowserRow.sortName)] {
        didSet { rebuildRows() }
    }
    @Published var extractContext: ExtractSheetContext?
    @Published var createContext: CreateSheetContext?
    @Published var previewItem: PreviewItem?
    @Published var alertMessage: String?
    @Published var busyMessage: String?
    @Published var isDropTargeted = false
    @Published var recents: [URL] = []
    @Published var toast: String?

    private(set) var lastPassword: String?
    private var loadToken = UUID()
    private var allEntries: [ArchiveEntry] = []
    private var entryByID: [Int: ArchiveEntry] = [:]
    private var folderChildren: [String: Set<String>] = [:]
    private var filesByParent: [String: [ArchiveEntry]] = [:]
    private var folderSizes: [String: Int64] = [:]
    private var folderFileCounts: [String: Int] = [:]
    private var explicitFolders: [String: ArchiveEntry] = [:]
    private var previewTempDirectory: URL?

    private static let recentsKey = "Unzipper.RecentArchives"
    private static let archiveExtensions: Set<String> = [
        "zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "cab", "iso", "jar"
    ]

    init() {
        loadRecents()
    }

    // MARK: - Loading

    static func looksLikeArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        let token = UUID()
        loadToken = token
        isLoading = true
        archiveURL = standardized
        listing = nil
        allEntries = []
        entryByID = [:]
        folderChildren = [:]
        filesByParent = [:]
        folderSizes = [:]
        folderFileCounts = [:]
        explicitFolders = [:]
        rows = []
        currentPath = ""
        selection.removeAll()
        searchText = ""
        lastPassword = nil

        Task {
            do {
                let result = try await ArchiveService.list(url: standardized)
                guard token == self.loadToken else { return }
                apply(result)
            } catch {
                guard token == self.loadToken else { return }
                isLoading = false
                archiveURL = nil
                alertMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ result: ArchiveListing) {
        listing = result
        allEntries = result.entries
        entryByID = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.id, $0) })
        buildIndex()
        currentPath = ""
        selection.removeAll()
        searchText = ""
        isLoading = false
        rebuildRows()
        addRecent(result.url)
    }

    func closeArchive() {
        loadToken = UUID()
        archiveURL = nil
        listing = nil
        allEntries = []
        entryByID = [:]
        folderChildren = [:]
        filesByParent = [:]
        folderSizes = [:]
        folderFileCounts = [:]
        explicitFolders = [:]
        rows = []
        currentPath = ""
        selection.removeAll()
        searchText = ""
        isLoading = false
        lastPassword = nil
        cleanupPreview()
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose an archive to open with Unzipper"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    // MARK: - Indexing

    private func buildIndex() {
        folderChildren.removeAll(keepingCapacity: true)
        filesByParent.removeAll(keepingCapacity: true)
        folderSizes.removeAll(keepingCapacity: true)
        folderFileCounts.removeAll(keepingCapacity: true)
        explicitFolders.removeAll(keepingCapacity: true)

        for entry in allEntries {
            // Archives are not required to contain directory entries, so create the
            // folder chain implied by every entry path.
            ensureAncestors(of: entry.path)

            if entry.isDirectory {
                explicitFolders[entry.path] = entry
                let parent = entry.parent
                folderChildren[parent, default: []].insert(entry.path)
            }

            var folder = entry.parent
            var ancestors: [String] = []
            while true {
                ancestors.append(folder)
                if folder.isEmpty { break }
                let pieces = folder.split(separator: "/", omittingEmptySubsequences: true)
                folder = pieces.dropLast().joined(separator: "/")
                if pieces.isEmpty { break }
            }

            for ancestor in ancestors {
                folderSizes[ancestor, default: 0] += entry.size
                if !entry.isDirectory {
                    folderFileCounts[ancestor, default: 0] += 1
                }
            }

            if !entry.isDirectory {
                filesByParent[entry.parent, default: []].append(entry)
            }
        }
    }

    private func ensureAncestors(of path: String) {
        var pieces = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !pieces.isEmpty else { return }
        pieces.removeLast()
        var parent = ""
        for piece in pieces {
            let child = parent.isEmpty ? piece : parent + "/" + piece
            folderChildren[parent, default: []].insert(child)
            parent = child
        }
    }

    // MARK: - Rows

    private func rebuildRows() {
        guard listing != nil else { rows = []; return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [BrowserRow] = []

        if query.isEmpty {
            for folderPath in folderChildren[currentPath] ?? [] {
                let name = folderPath.split(separator: "/").last.map(String.init) ?? folderPath
                let entry = explicitFolders[folderPath]
                result.append(BrowserRow(path: folderPath,
                                         name: name,
                                         isDirectory: true,
                                         size: folderSizes[folderPath] ?? 0,
                                         packedSize: nil,
                                         modified: entry?.modified,
                                         isEncrypted: false,
                                         entryIndex: entry?.id))
            }
            for entry in filesByParent[currentPath] ?? [] {
                result.append(BrowserRow(path: entry.path,
                                         name: entry.name,
                                         isDirectory: false,
                                         size: entry.size,
                                         packedSize: entry.compressedSize,
                                         modified: entry.modified,
                                         isEncrypted: entry.isEncrypted,
                                         entryIndex: entry.id))
            }
        } else {
            for entry in allEntries {
                guard entry.path.localizedCaseInsensitiveContains(query) else { continue }
                result.append(BrowserRow(path: entry.path,
                                         name: entry.path,
                                         isDirectory: entry.isDirectory,
                                         size: entry.isDirectory ? (folderSizes[entry.path] ?? 0) : entry.size,
                                         packedSize: entry.compressedSize,
                                         modified: entry.modified,
                                         isEncrypted: entry.isEncrypted,
                                         entryIndex: entry.id))
            }
            for folderPath in folderChildren.keys where !folderPath.isEmpty {
                guard !explicitFolders.keys.contains(folderPath),
                      folderPath.localizedCaseInsensitiveContains(query) else { continue }
                result.append(BrowserRow(path: folderPath,
                                         name: folderPath,
                                         isDirectory: true,
                                         size: folderSizes[folderPath] ?? 0,
                                         packedSize: nil,
                                         modified: nil,
                                         isEncrypted: false,
                                         entryIndex: nil))
            }
        }

        rows = result.sorted(using: sortOrder)
    }

    func navigate(to path: String) {
        if !searchText.isEmpty { searchText = "" }
        currentPath = path
        selection.removeAll()
        rebuildRows()
    }

    func goUp() {
        guard !currentPath.isEmpty else { return }
        let pieces = currentPath.split(separator: "/", omittingEmptySubsequences: true)
        navigate(to: pieces.dropLast().joined(separator: "/"))
    }

    func activate(_ ids: Set<String>) {
        guard let id = ids.first, let row = rows.first(where: { $0.id == id }) else { return }
        if row.isDirectory {
            navigate(to: row.path)
        } else {
            preview(row)
        }
    }

    func openSelection() {
        if let row = rows.first(where: { selection.contains($0.id) }) {
            if row.isDirectory { navigate(to: row.path) } else { preview(row) }
        }
    }

    // MARK: - Status

    var windowTitle: String {
        archiveURL?.lastPathComponent ?? "Unzipper"
    }

    var windowSubtitle: String {
        guard let listing else { return "Open or drop an archive" }
        let count = listing.entries.filter { !$0.isDirectory }.count
        return "\(listing.displayFormat) · \(Formatting.items(count))"
    }

    var breadcrumb: [(title: String, path: String)] {
        var items: [(String, String)] = [(archiveURL?.lastPathComponent ?? "Archive", "")]
        guard !currentPath.isEmpty else { return items }
        var path = ""
        for piece in currentPath.split(separator: "/") {
            path = path.isEmpty ? String(piece) : path + "/" + piece
            items.append((String(piece), path))
        }
        return items
    }

    var currentFileCount: Int {
        filesByParent[currentPath]?.count ?? 0
    }

    var currentFolderCount: Int {
        folderChildren[currentPath]?.count ?? 0
    }

    var currentFolderSize: Int64 {
        folderSizes[currentPath] ?? 0
    }

    var totalEntryCount: Int {
        allEntries.filter { !$0.isDirectory }.count
    }

    var selectedRows: [BrowserRow] {
        rows.filter { selection.contains($0.id) }
    }

    var selectionText: String {
        let selected = selectedRows
        if selected.isEmpty {
            if !searchText.isEmpty { return "\(rows.count) \(rows.count == 1 ? "result" : "results")" }
            let files = currentFileCount
            let folders = currentFolderCount
            return "\(files) \(files == 1 ? "file" : "files"), \(folders) \(folders == 1 ? "folder" : "folders")"
        }
        let bytes = selected.reduce(Int64(0)) { $0 + $1.size }
        return "\(selected.count) selected · \(Formatting.size(bytes))"
    }

    var footerText: String {
        guard let listing else { return "" }
        if !searchText.isEmpty || !currentPath.isEmpty {
            return "\(listing.displayFormat) · \(Formatting.size(listing.totalSize))"
        }
        var text = "\(listing.displayFormat) · \(Formatting.size(listing.totalSize))"
        if listing.totalCompressed != nil {
            text += " · \(Formatting.ratio(listing.totalSize, listing.totalCompressed)) saved"
        }
        return text
    }

    // MARK: - Extraction

    func extractAll() {
        guard let listing, let archiveURL else { return }
        let indices = listing.entries.map(\.id)
        presentExtraction(indices: indices,
                          archiveURL: archiveURL,
                          label: Formatting.items(indices.count))
    }

    func extractSelected() {
        guard let archiveURL else { return }
        let selected = selectedRows
        guard !selected.isEmpty else { NSSound.beep(); return }
        let indices = entryIndices(for: selected)
        guard !indices.isEmpty else { NSSound.beep(); return }
        let label = selected.count == 1 ? (selected[0].isDirectory ? "folder “\(selected[0].name)”" : "“\(selected[0].name)”")
                                       : Formatting.items(selected.count)
        presentExtraction(indices: indices, archiveURL: archiveURL, label: label)
    }

    private func presentExtraction(indices: [Int], archiveURL: URL, label: String) {
        guard !indices.isEmpty else { NSSound.beep(); return }
        let bytes = indices.reduce(Int64(0)) { $0 + (entryByID[$1]?.size ?? 0) }
        let encrypted = indices.contains { entryByID[$0]?.isEncrypted == true }
        extractContext = ExtractSheetContext(archiveURL: archiveURL,
                                             archiveName: archiveURL.lastPathComponent,
                                             indices: indices,
                                             totalEntries: indices.count,
                                             totalBytes: bytes,
                                             containsEncrypted: encrypted,
                                             selectionLabel: label)
    }

    func entryIndices(for rows: [BrowserRow]) -> [Int] {
        var result = Set<Int>()
        for row in rows {
            if row.isDirectory {
                let prefix = row.path + "/"
                for entry in allEntries where entry.path == row.path || entry.path.hasPrefix(prefix) {
                    result.insert(entry.id)
                }
            } else if let index = row.entryIndex {
                result.insert(index)
            }
        }
        return result.sorted()
    }

    func noteExtraction(password: String?) {
        if let password, !password.isEmpty { lastPassword = password }
    }

    // MARK: - Preview

    func preview(_ row: BrowserRow) {
        guard !row.isDirectory,
              let entry = row.entryIndex.flatMap({ entryByID[$0] }),
              let archiveURL else { return }
        if entry.isEncrypted, lastPassword == nil {
            alertMessage = "“\(entry.name)” is encrypted. Use Extract to enter its password first, then preview it."
            return
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnzipperPreview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        } catch {
            alertMessage = "Could not prepare a preview."
            return
        }

        cleanupPreview()
        previewTempDirectory = temp
        busyMessage = "Preparing preview…"

        let request = ExtractionRequest(archiveURL: archiveURL,
                                        destination: temp,
                                        entryIndices: [entry.id],
                                        totalEntries: 1,
                                        password: lastPassword,
                                        overwrite: true,
                                        totalBytes: entry.size)
        Task {
            do {
                try await ArchiveService.extract(request, cancelFlag: CancelFlag()) { _ in }
                busyMessage = nil
                let extracted = temp.appendingPathComponent(entry.path)
                guard FileManager.default.fileExists(atPath: extracted.path) else {
                    throw ArchiveError.message("The preview file could not be written.")
                }
                previewItem = PreviewItem(url: extracted,
                                          title: entry.name,
                                          subtitle: "\(Formatting.size(entry.size)) · \(entry.path)",
                                          tempDirectory: temp)
            } catch {
                busyMessage = nil
                cleanupPreview()
                alertMessage = error.localizedDescription
            }
        }
    }

    func quickLookSelection() {
        guard let row = rows.first(where: { selection.contains($0.id) }) else { return }
        preview(row)
    }

    func selectAllRows() {
        guard archiveURL != nil else { return }
        selection = Set(rows.map(\.id))
    }

    func focusSearch() {
        guard archiveURL != nil else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if let field = Self.findSearchField(in: window.contentView?.superview) {
            window.makeFirstResponder(field)
        }
    }

    private static func findSearchField(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSSearchField { return view }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
    }

    func cleanupPreview() {
        if let temp = previewTempDirectory {
            try? FileManager.default.removeItem(at: temp)
            previewTempDirectory = nil
        }
    }

    // MARK: - Creation

    func presentNewArchive(items: [URL] = []) {
        createContext = CreateSheetContext(items: items)
    }

    func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1, Self.looksLikeArchive(urls[0]) {
            open(urls[0])
        } else if urls.allSatisfy({ Self.looksLikeArchive($0) }) {
            open(urls[0])
        } else {
            presentNewArchive(items: urls)
        }
    }

    // MARK: - Recents

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        recents = paths.map(URL.init(fileURLWithPath:)).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func addRecent(_ url: URL) {
        var updated = recents.filter { $0.standardizedFileURL != url.standardizedFileURL }
        updated.insert(url.standardizedFileURL, at: 0)
        recents = Array(updated.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: Self.recentsKey)
    }

    func removeRecent(_ url: URL) {
        recents.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recents.map(\.path), forKey: Self.recentsKey)
    }

    // MARK: - Misc

    func revealArchive() {
        guard let archiveURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == text { toast = nil }
        }
    }
}

enum Formatting {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        if bytes == 0 { return "Zero bytes" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    static func compactSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        if bytes == 0 { return "0" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    static func ratio(_ size: Int64, _ packed: Int64?) -> String {
        guard let packed, size > 0, packed > 0 else { return "—" }
        let percent = max(0, (1 - (Double(packed) / Double(size))) * 100)
        return String(format: "%.0f%%", percent)
    }

    static let tableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func tableDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return tableDateFormatter.string(from: date)
    }

    static func items(_ count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items")"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }
}
