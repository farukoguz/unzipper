import AppKit
import UniformTypeIdentifiers

/// Cached Finder icons for archive entries.
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
