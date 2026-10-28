import Foundation

/// Presentation strings shared by the browser, sheets, and status views.
public enum Formatting {
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

    public static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        if bytes == 0 { return "Zero bytes" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    public static func compactSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        if bytes == 0 { return "0" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    public static func ratio(_ size: Int64, _ packed: Int64?) -> String {
        guard let packed, size > 0, packed > 0 else { return "—" }
        let percent = max(0, (1 - (Double(packed) / Double(size))) * 100)
        return String(format: "%.0f%%", percent)
    }

    public static let tableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static func tableDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return tableDateFormatter.string(from: date)
    }

    public static func items(_ count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items")"
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }
}
