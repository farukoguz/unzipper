import Foundation

/// Path helpers for the slash-separated, root-relative paths used inside archives.
public enum ArchivePath {
    public static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public static func name(of path: String) -> String {
        components(of: path).last ?? path
    }

    public static func parent(of path: String) -> String {
        components(of: path).dropLast().joined(separator: "/")
    }

    /// The folder itself and every folder above it, nearest first, ending at the
    /// archive root (`""`). For `a/b/file.txt` this returns `["a/b", "a", ""]`.
    public static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var folder = parent(of: path)
        result.append(folder)
        while !folder.isEmpty {
            folder = parent(of: folder)
            result.append(folder)
        }
        return result
    }

    /// Breadcrumb components for a folder path, excluding the archive root.
    public static func breadcrumbs(for folder: String) -> [(name: String, path: String)] {
        var path = ""
        return components(of: folder).map { piece in
            path = path.isEmpty ? piece : path + "/" + piece
            return (piece, path)
        }
    }
}
