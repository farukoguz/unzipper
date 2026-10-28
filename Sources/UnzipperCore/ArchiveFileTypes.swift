import Foundation

public enum ArchiveFileTypes {
    public static let supportedExtensions: Set<String> = [
        "zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "cab", "iso", "jar"
    ]

    public static func isArchive(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
