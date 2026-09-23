import Foundation

/// Settings → Xcode's "Download Xcode" list, folded by Xcode major version so
/// a list that reaches back to Xcode 2.3 is a few lines until opened.
///
/// Each major is paired with the macOS whose SDK its later releases carry:
/// Xcode 26 and later share macOS's number, Xcode 12–16 go with macOS 11–15.
/// From the xcodereleases index's `sdks.macOS`, 2026-09-23: the newest macOS
/// SDK in each of Xcode 12…16 is 11…15 (an x.0 may still carry the one before —
/// Xcode 13.0 has the macOS 11 SDK). Everything before Xcode 12 is one "older"
/// group.
public struct XcodeDownloadGroup: Sendable, Equatable, Identifiable {
    /// The Xcode major; nil for the "older" group.
    public let major: Int?
    /// "26", "15" — the macOS this major came with; nil for the "older" group.
    public let macOS: String?
    /// In the list's own order.
    public let items: [XcodeDownloadItem]

    public var id: String { major.map(String.init) ?? "older" }

    /// The oldest major kept as its own group; below it, "older".
    static let oldestOwnGroup = 12

    /// Group `items`, keeping their order within each group; groups newest
    /// first, "older" last. Pure.
    public static func grouped(_ items: [XcodeDownloadItem]) -> [XcodeDownloadGroup] {
        var order: [Int?] = []
        var byMajor: [Int?: [XcodeDownloadItem]] = [:]
        for item in items {
            let key = major(of: item.displayVersion).flatMap { $0 >= oldestOwnGroup ? $0 : nil }
            if byMajor[key] == nil { order.append(key) }
            byMajor[key, default: []].append(item)
        }
        return order
            .sorted { ($0 ?? Int.min) > ($1 ?? Int.min) }
            .map { XcodeDownloadGroup(major: $0, macOS: $0.flatMap(macOS(for:)), items: byMajor[$0] ?? []) }
    }

    /// The group to show open: the one that came with this Mac's macOS, else
    /// the newest.
    public static func defaultOpen(
        in groups: [XcodeDownloadGroup], hostMacOSMajor: Int
    ) -> XcodeDownloadGroup.ID? {
        (groups.first { $0.macOS == String(hostMacOSMajor) } ?? groups.first)?.id
    }

    /// "27.1 beta 1 (27A9269)" → 27.
    static func major(of displayVersion: String) -> Int? {
        Int(displayVersion.prefix { $0.isNumber })
    }

    /// Xcode 26 and later: the same number. Xcode 12–16: one below.
    static func macOS(for major: Int) -> String? {
        if major >= 26 { return String(major) }
        if (oldestOwnGroup...16).contains(major) { return String(major - 1) }
        return nil
    }
}
