import Foundation

enum com_rogueamoeba_audiohijack {
    static let bundleID = "com.rogueamoeba.audiohijack"

    // The vendor's download page redirects Sparkle clients to its archive.
    static let downloadHeaders = ["User-Agent": "\(Downloader.userAgent) Sparkle"]

    static func matchesFeed(bundleID: String?, feedURL: URL) -> Bool {
        bundleID?.lowercased() == self.bundleID
            && feedURL == SparkleFeedCatalog.feed(forBundleID: self.bundleID)
    }

    static let set = AppRecipeSet(
        family: "com-rogueamoeba-audiohijack",
        sparkleFeeds: [
            // History: docs/app-audits/com-rogueamoeba-audiohijack.md#历史与实测
            // Protein configures Sparkle in code. The public stable appcast selects
            // an OS-compatible build using the undotted macOS version in `system`.
            bundleID: URL(string:
                "https://rogueamoeba.net/ping/versionCheck.cgi?format=sparkle&bundleid=com.rogueamoeba.audiohijack&platform=osx&arch=arm64&system=__HOST_OS_COMPACT_VERSION__")!,
        ],
        changelogPages: [
            bundleID: URL(string: "https://rogueamoeba.com/support/releasenotes/?product=Audio+Hijack")!,
        ])
}
