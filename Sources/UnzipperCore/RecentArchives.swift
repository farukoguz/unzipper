import Foundation

/// Pure recent-document list. Persistence is the caller's concern.
public struct RecentArchives: Sendable, Equatable {
    public private(set) var urls: [URL]
    public let limit: Int

    public init(urls: [URL] = [], limit: Int = 8) {
        let cap = max(0, limit)
        self.limit = cap
        var seen = Set<URL>()
        self.urls = urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0).inserted }
            .prefix(cap)
            .map { $0 }
    }

    @discardableResult
    public mutating func add(_ url: URL) -> [URL] {
        let standardized = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standardized }
        urls.insert(standardized, at: 0)
        if urls.count > limit {
            urls.removeLast(urls.count - limit)
        }
        return urls
    }

    @discardableResult
    public mutating func remove(_ url: URL) -> [URL] {
        let standardized = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standardized }
        return urls
    }
}
