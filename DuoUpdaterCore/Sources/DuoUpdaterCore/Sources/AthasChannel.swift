import Foundation

enum AthasChannel {
    static let bundleID = "com.code.athas"

    static func resolve(
        bundleStrings: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ResolvedChannel {
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let legacy = support.appendingPathComponent("com.code.athas/settings.json")
        let native = support.appendingPathComponent("dev.athas.app/settings.json")
        // GPUI starts at 0.19. On first launch it reads the Tauri profile if its
        // own file is absent. A rolled-back Tauri copy only reads its own profile.
        let core = bundleStrings["CFBundleShortVersionString"]?.split(separator: "-", maxSplits: 1).first
        // 0.16.2 introduced the channel picker and request header. An older
        // Tauri build does not honor a beta choice left by a newer installation.
        if let core, VersionComparator.isNewer("0.16.2", than: String(core)) {
            return ResolvedChannel(channel: .stable)
        }
        let isTauri = core.map { VersionComparator.isNewer("0.19.0", than: String($0)) } ?? false
        let settings = isTauri ? read(legacy) : read(native) ?? read(legacy)
        let channel = settings?["updateChannel"] as? String
        return ResolvedChannel(channel: channel == "beta" ? .beta : .stable)
    }

    private static func read(_ url: URL) -> [String: Any]? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        // A readable GPUI file takes precedence even with a missing or invalid
        // channel key. Do not resurrect a beta opt-in from the old profile.
        let limit = 1024 * 1024
        guard let data = try? file.read(upToCount: limit + 1), data.count <= limit else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any] ?? [:]
    }
}
