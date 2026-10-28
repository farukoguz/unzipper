import Foundation

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
