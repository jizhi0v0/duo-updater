import Foundation

/// Apple's own list of developer downloads — the data behind
/// developer.apple.com/download/all — as far as Xcode archives go.
///
/// `POST developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action`
/// with the Apple Developer session. Undocumented (xcodes calls this source the
/// "more fragile" one), so everything here fails soft: anything unreadable
/// parses to an empty list, and the caller falls back to the xcodereleases index.
///
/// Measured 2026-09-23 (signed in): 1601 downloads, 259 of them Xcode, back to
/// Xcode 2.3 (2006); 27.1 beta was listed at 17:07 UTC, seven minutes after
/// Apple announced it (the index took ~1h22m). ~190 KB on the wire (gzip of
/// 1.79 MB), `cache-control: no-store` — so it is fetched only when the user
/// opens or refreshes the list, never on a timer.
public enum AppleDeveloperDownloadList {
    public static let endpoint = URL(
        string: "https://developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action")!

    public struct Release: Sendable, Equatable {
        /// "27.1 beta" — Apple's name without "Xcode ".
        public let displayName: String
        public let isPrerelease: Bool
        public let published: Date?
        public let requiresMacOS: String?
        public let archives: [Archive]
    }

    public struct Archive: Sendable, Equatable {
        public let path: String
        public let arch: Arch
    }

    public enum Arch: Sendable, Equatable { case appleSilicon, universal, unlabelled }

    /// The `.xip` Xcode releases in a `listDownloads` response. Pure.
    public static func parse(_ data: Data) -> [Release] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["resultCode"] as? Int ?? 0) == 0,
              let downloads = root["downloads"] as? [[String: Any]]
        else { return [] }
        return downloads.compactMap { download -> Release? in
            guard let name = download["name"] as? String,
                  name.range(of: #"^Xcode [0-9]"#, options: .regularExpression) != nil
            else { return nil }
            let files = download["files"] as? [[String: Any]] ?? []
            let description = download["description"] as? String
            // "…requires a Mac running macOS Tahoe 26.6 or later on Apple silicon."
            // (27.1 beta): its one archive is unlabelled but not for Intel.
            let appleSiliconOnly = description?.contains("or later on Apple silicon") == true
            let archives = files.compactMap { file -> Archive? in
                guard let path = file["remotePath"] as? String, path.hasSuffix(".xip") else { return nil }
                let fileName = (file["filename"] as? String ?? path).lowercased()
                let arch: Arch = fileName.contains("apple silicon") || path.contains("_Apple_silicon")
                    ? .appleSilicon
                    : (fileName.contains("universal") || path.contains("_Universal") ? .universal
                       : (appleSiliconOnly ? .appleSilicon : .unlabelled))
                return Archive(path: path, arch: arch)
            }
            guard !archives.isEmpty else { return nil }
            return Release(
                displayName: String(name.dropFirst("Xcode ".count)),
                isPrerelease: isPrerelease(name),
                published: (download["datePublished"] as? String).flatMap(date(from:)),
                requiresMacOS: description.flatMap(requiredMacOS(in:)),
                archives: archives)
        }
    }

    /// From the name, not `isReleased`: Apple's list has `isReleased: 0` on the
    /// final Xcode 16.4 as well as on betas and RCs (2026-09-23).
    static func isPrerelease(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("beta") || lower.contains("release candidate")
            || lower.range(of: #"\brc\b"#, options: .regularExpression) != nil
    }

    /// "…requires a Mac running macOS Tahoe 26.6 or later…" → "26.6".
    static func requiredMacOS(in description: String) -> String? {
        guard let range = description.range(
            of: #"macOS [A-Za-z ]*?([0-9]+(\.[0-9]+)*) or later"#, options: .regularExpression)
        else { return nil }
        let match = String(description[range])
        return match.range(of: #"[0-9]+(\.[0-9]+)*"#, options: .regularExpression).map { String(match[$0]) }
    }

    /// `datePublished`, "09/18/26 17:07", in UTC: 27.1 beta reads 17:07 against
    /// Apple's 10:00 PDT (17:00 UTC) announcement (2026-09-23).
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "MM/dd/yy HH:mm"
        return formatter.date(from: string)
    }
}
