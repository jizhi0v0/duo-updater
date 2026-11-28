import Foundation

enum com_rawtherapee_rawtherapee5 {
    private static let legacyID = "com.rawtherapee.RawTherapee"
    private static let currentID = "com.rawtherapee.rawtherapee5"
    private static let archives = URL(string: "https://rawtherapee.com/shared/builds/mac/")!
    private static let downloads = URL(string: "https://rawtherapee.com/downloads/")!
    private static let number = #"[0-9]+\.[0-9]+(?:\.[0-9]+)?"#
    private static let stableVersion = #"\A\#(number)\z"#
    private static let link = #"<a href="RawTherapee_(?:macOS|MacOS)_"#

    // History: docs/app-audits/com-rawtherapee-rawtherapee5.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-rawtherapee-rawtherapee5",
        probes: [
            newestStable(legacyID),
            // The latest stable Universal archive may have a newer Apple
            // Silicon floor than this Mac. The exact published Sequoia
            // fallbacks stay eligible only while their archives are listed.
            fallback(version: "5.12", floor: "15.4"),
            fallback(version: "5.11", floor: "12.3"),
            newestStable(currentID),
        ],
        changelogs: [notes(legacyID), notes(currentID)])

    private static func newestStable(_ id: String) -> VendorProbeRecipe {
        // The version and Apple Silicon minimum come from the same Universal
        // package link. The directory is alphabetical, not version-ordered.
        VendorProbeRecipe(
            bundleID: id,
            url: archives,
            mode: .responseBody,
            versionPattern: #"\#(link)\#(number)_Universal_(\#(number))\.zip">"#,
            downloadURL: downloads,
            selectHighest: true,
            minimumSystemVersionPattern: #"\#(link)(\#(number))_Universal_\#(number)\.zip">"#,
            entryStartPattern: link,
            hostRequirement: .init(architectures: [.arm64]),
            installedVersionPattern: stableVersion)
    }

    private static func fallback(version: String, floor: String) -> VendorProbeRecipe {
        let escapedVersion = NSRegularExpression.escapedPattern(for: version)
        let escapedFloor = NSRegularExpression.escapedPattern(for: floor)
        return VendorProbeRecipe(
            bundleID: legacyID,
            url: archives,
            mode: .responseBody,
            versionPattern: #"\#(link)\#(escapedFloor)_Universal_(\#(escapedVersion))\.zip">"#,
            downloadURL: downloads.appendingPathComponent(version, isDirectory: true),
            variant: "compatible-\(version)",
            hostRequirement: .init(minimumSystemVersion: floor, architectures: [.arm64]),
            installedVersionPattern: stableVersion)
    }

    private static func notes(_ id: String) -> ChangelogRecipe {
        // The download page has version-specific release notes. Use its own
        // headings and stop before installation instructions and checksums.
        ChangelogRecipe(
            bundleID: id,
            source: downloads,
            entryPattern: #"<h1 class="page-title">RawTherapee v(?<version>\#(number))</h1>"#
                + #".*?Download RawTherapee version \k<version> released on\s+(?<date>[A-Za-z]+ \d{1,2}, \d{4})\."#
                + #".*?(?<body><h2 id="new-features">.*?)(?=<h2 id="(?:installation-instructions|sha-256)")"#,
            itemPatterns: [#"<(?:li|p)\b[^>]*>(?<item>.*?)(?=</(?:li|p)>|<[uo]l\b)"#],
            channel: .stable,
            sourceTemplate: "https://rawtherapee.com/downloads/{version}/",
            headingPattern: #"<h2\b[^>]*>\s*<a\b[^>]*\baria-label="Permalink to (?<heading>[^"]+)""#)
    }
}
