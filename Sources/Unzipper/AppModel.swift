import AppKit
import Foundation
import SwiftUI
import UnzipperCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var archiveURL: URL?
    @Published private(set) var listing: ArchiveListing?
    @Published private(set) var rows: [ArchiveRow] = []
    @Published private(set) var currentPath = ""
    @Published private(set) var isLoading = false
    @Published var selection = Set<String>()
    @Published var searchText = "" { didSet { if searchText != oldValue { selection.removeAll(); rebuildRows() } } }
    @Published var sortOrder: [KeyPathComparator<ArchiveRow>] = [KeyPathComparator(\ArchiveRow.sortName)] {
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
    private var index = ArchiveIndex(entries: [])
    private var previewTempDirectory: URL?
    private var previewTask: Task<Void, Never>?
    private var previewCancelFlag: CancelFlag?
    private var previewGeneration = UUID()

    private static let recentsKey = "Unzipper.RecentArchives"
    private static let recentLimit = 8

    init() {
        loadRecents()
    }

    // MARK: - Loading

    func open(_ url: URL) {
        let standardized = url.standardizedFileURL
        let token = UUID()
        loadToken = token
        archiveURL = standardized
        resetLoadedState()
        isLoading = true

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
        index = ArchiveIndex(entries: result.entries)
        isLoading = false
        rebuildRows()
        addRecent(result.url)
    }

    func closeArchive() {
        loadToken = UUID()
        archiveURL = nil
        resetLoadedState()
    }

    private func resetLoadedState() {
        listing = nil
        index = ArchiveIndex(entries: [])
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

    // MARK: - Rows

    private func rebuildRows() {
        guard listing != nil else {
            rows = []
            return
        }
        rows = ArchiveBrowser.rows(in: currentPath,
                                   index: index,
                                   query: searchText,
                                   sortOrder: sortOrder)
    }

    func navigate(to path: String) {
        if !searchText.isEmpty { searchText = "" }
        currentPath = path
        selection.removeAll()
        rebuildRows()
    }

    func goUp() {
        guard !currentPath.isEmpty else { return }
        navigate(to: ArchivePath.parent(of: currentPath))
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
        guard let row = rows.first(where: { selection.contains($0.id) }) else { return }
        if row.isDirectory { navigate(to: row.path) } else { preview(row) }
    }

    // MARK: - Status

    var windowTitle: String {
        archiveURL?.lastPathComponent ?? "Unzipper"
    }

    var windowSubtitle: String {
        guard let listing else { return "Open or drop an archive" }
        return "\(listing.displayFormat) · \(Formatting.items(index.totalFileCount))"
    }

    var breadcrumb: [(title: String, path: String)] {
        var items: [(String, String)] = [(archiveURL?.lastPathComponent ?? "Archive", "")]
        items.append(contentsOf: ArchivePath.breadcrumbs(for: currentPath))
        return items
    }

    var currentFileCount: Int {
        index.files(in: currentPath).count
    }

    var currentFolderCount: Int {
        index.children(of: currentPath).count
    }

    var currentFolderSize: Int64 {
        index.folderSize(currentPath)
    }

    var totalEntryCount: Int {
        index.totalFileCount
    }

    var selectedRows: [ArchiveRow] {
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
        let label = selected.count == 1
            ? (selected[0].isDirectory ? "folder “\(selected[0].name)”" : "“\(selected[0].name)”")
            : Formatting.items(selected.count)
        presentExtraction(indices: indices, archiveURL: archiveURL, label: label)
    }

    private func presentExtraction(indices: [Int], archiveURL: URL, label: String) {
        guard !indices.isEmpty else { NSSound.beep(); return }
        let bytes = indices.reduce(Int64(0)) { $0 + (index.entry(withID: $1)?.size ?? 0) }
        let encrypted = indices.contains { index.entry(withID: $0)?.isEncrypted == true }
        extractContext = ExtractSheetContext(archiveURL: archiveURL,
                                             archiveName: archiveURL.lastPathComponent,
                                             indices: indices,
                                             totalEntries: indices.count,
                                             totalBytes: bytes,
                                             containsEncrypted: encrypted,
                                             selectionLabel: label)
    }

    func entryIndices(for rows: [ArchiveRow]) -> [Int] {
        index.indices(for: rows)
    }

    func noteExtraction(password: String?) {
        if let password, !password.isEmpty { lastPassword = password }
    }

    // MARK: - Preview

    func preview(_ row: ArchiveRow) {
        guard !row.isDirectory,
              let entry = row.entryIndex.flatMap({ index.entry(withID: $0) }),
              let archiveURL else { return }
        if entry.isEncrypted, lastPassword == nil {
            alertMessage = "“\(entry.name)” is encrypted. Use Extract to enter its password first, then preview it."
            return
        }

        cleanupPreview()

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnzipperPreview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        } catch {
            alertMessage = "Could not prepare a preview."
            return
        }

        let generation = UUID()
        let cancelFlag = CancelFlag()
        previewGeneration = generation
        previewCancelFlag = cancelFlag
        previewTempDirectory = temp
        busyMessage = "Preparing preview…"

        let request = ExtractionRequest(archiveURL: archiveURL,
                                        destination: temp,
                                        entryIndices: [entry.id],
                                        totalEntries: 1,
                                        password: lastPassword,
                                        overwrite: true,
                                        totalBytes: entry.size)
        previewTask = Task { [weak self] in
            do {
                try await ArchiveService.extract(request, cancelFlag: cancelFlag) { _ in }
                guard let self, self.previewGeneration == generation else {
                    try? FileManager.default.removeItem(at: temp)
                    return
                }
                self.busyMessage = nil
                self.previewTask = nil
                self.previewCancelFlag = nil
                let extracted = temp.appendingPathComponent(entry.path)
                guard FileManager.default.fileExists(atPath: extracted.path) else {
                    throw ArchiveError.message("The preview file could not be written.")
                }
                self.previewItem = PreviewItem(url: extracted,
                                               title: entry.name,
                                               subtitle: "\(Formatting.size(entry.size)) · \(entry.path)",
                                               tempDirectory: temp)
            } catch {
                guard let self, self.previewGeneration == generation else {
                    try? FileManager.default.removeItem(at: temp)
                    return
                }
                self.busyMessage = nil
                self.previewTask = nil
                self.previewCancelFlag = nil
                if self.previewTempDirectory == temp {
                    try? FileManager.default.removeItem(at: temp)
                    self.previewTempDirectory = nil
                }
                self.alertMessage = error.localizedDescription
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
        previewCancelFlag?.cancel()
        previewCancelFlag = nil
        previewTask?.cancel()
        previewTask = nil
        previewGeneration = UUID()
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
        if urls.count == 1, ArchiveFileTypes.isArchive(urls[0]) {
            open(urls[0])
        } else if urls.allSatisfy(ArchiveFileTypes.isArchive) {
            open(urls[0])
        } else {
            presentNewArchive(items: urls)
        }
    }

    // MARK: - Recents

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        let stored = RecentArchives(urls: paths.map(URL.init(fileURLWithPath:)),
                                     limit: Self.recentLimit).urls
        recents = stored.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecent(_ url: URL) {
        var store = RecentArchives(urls: recents, limit: Self.recentLimit)
        store.add(url)
        recents = store.urls
        persistRecents()
    }

    func removeRecent(_ url: URL) {
        var store = RecentArchives(urls: recents, limit: Self.recentLimit)
        store.remove(url)
        recents = store.urls
        persistRecents()
    }

    private func persistRecents() {
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
