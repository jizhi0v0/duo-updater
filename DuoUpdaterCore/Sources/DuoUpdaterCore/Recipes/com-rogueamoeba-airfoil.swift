import Foundation

enum RogueAmoebaAppcast {
    // Preserve the spelling the vendor uses in its requests. Catalog keys are lowercase.
    private static let products: [(id: String, name: String, major: Int)] = [
        ("com.rogueamoeba.Airfoil", "Airfoil for Mac", 5),
        ("com.rogueamoeba.AirfoilSpeakers", "Airfoil Satellite for Mac", 5),
        ("com.rogueamoeba.farrago", "Farrago", 2),
        ("com.rogueamoeba.Fission", "Fission", 2),
        ("com.rogueamoeba.Loopback", "Loopback", 2),
        ("com.rogueamoeba.Piezo", "Piezo", 1),
        ("com.rogueamoeba.soundsource", "SoundSource", 6),
    ]
    private static let soundSourceID = "com.rogueamoeba.soundsource"
    private static let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id.lowercased(), $0) })
    private static let legacySoundSource = feedTemplate(id: soundSourceID, major: 5)

    // History: docs/app-audits/com-rogueamoeba-airfoil.md#历史与实测
    // The vendor's public appcast selects the track from the major component of
    // the numeric version query. Use its first release value for a known track.
    private static func feedTemplate(id: String, major: Int) -> URL {
        URL(string: "https://rogueamoeba.net/ping/versionCheck.cgi?format=sparkle&bundleid=\(id)&platform=osx&arch=arm64&system=__HOST_OS_COMPACT_VERSION__&version=\(major * 1_000_000 + 8_000)")!
    }

    private static func major(of version: String?) -> Int? {
        guard let version, let first = version.split(separator: ".", omittingEmptySubsequences: false).first
        else { return nil }
        return Int(first)
    }

    /// Select the fill-in before scanning any feed. An old paid edition sharing the
    /// ID with a current one must never inherit the current edition's catalog URL.
    static func installedFeed(bundleID: String, version: String, current: URL?) -> URL? {
        guard let product = byID[bundleID] else { return current }
        let installedMajor = major(of: version)
        if installedMajor == product.major { return current }
        if bundleID == soundSourceID, installedMajor == 5 {
            return SparkleFeedCatalog.resolveHostOS(in: legacySoundSource)
        }
        return nil
    }

    static func matchesFeed(bundleID: String?, feedURL: URL) -> Bool {
        com_rogueamoeba_audiohijack.matchesFeed(bundleID: bundleID, feedURL: feedURL)
            || offeredMajor(bundleID: bundleID, feedURL: feedURL) != nil
    }

    static func offeredMajor(bundleID: String?, feedURL: URL) -> Int? {
        guard let id = bundleID?.lowercased(), let product = byID[id] else { return nil }
        if feedURL == SparkleFeedCatalog.feed(forBundleID: id) { return product.major }
        if id == soundSourceID, feedURL == SparkleFeedCatalog.resolveHostOS(in: legacySoundSource) { return 5 }
        return nil
    }

    static func acceptsVersion(_ version: String?, onMajor expected: Int) -> Bool {
        major(of: version) == expected
    }

    static func maximumSystemVersion(bundleID: String?, offeredMajor: Int) -> String? {
        // SoundSource 5 is retired and the last signed app declares
        // RAMaximumButNotSupportedSystemVersion=27.0. Sparkle's maximum is inclusive.
        bundleID?.lowercased() == soundSourceID && offeredMajor == 5 ? "26.99.99" : nil
    }

    static let downloadHeaders = ["User-Agent": "\(Downloader.userAgent) Sparkle"]

    /// Protein embeds a whole web page. Keep the release entry, dropping its
    /// document header, stylesheets and the page heading that repeats the version.
    static func releaseNotesBody(_ html: String) -> String {
        guard let entry = html.range(of: #"<div\b[^>]*\bra-version\s*="#,
                                     options: [.regularExpression, .caseInsensitive]),
              let end = html.range(of: "</body>", options: .caseInsensitive,
                                   range: entry.upperBound..<html.endIndex)
        else { return html }
        return String(html[entry.lowerBound..<end.lowerBound])
    }

    static let set = AppRecipeSet(
        family: "com-rogueamoeba-airfoil",
        sparkleFeeds: Dictionary(uniqueKeysWithValues: products.map {
            ($0.id.lowercased(), feedTemplate(id: $0.id, major: $0.major))
        }),
        changelogPages: Dictionary(uniqueKeysWithValues: products.map {
            let name = $0.name.replacingOccurrences(of: " ", with: "+")
            return ($0.id.lowercased(), URL(string: "https://rogueamoeba.com/support/releasenotes/?product=\(name)")!)
        }))
}
