import Foundation

enum com_rawtherapee_rawtherapee5 {
    static let legacyID = "com.rawtherapee.RawTherapee"
    private static let currentID = "com.rawtherapee.rawtherapee5"
    private static let archives = URL(string: "https://rawtherapee.com/shared/builds/mac/")!
    private static let downloads = URL(string: "https://rawtherapee.com/downloads/")!
    private static let number = #"[0-9]+\.[0-9]+(?:\.[0-9]+)?"#
    private static let stableVersion = #"\A\#(number)\z"#
    private static let link = #"<a href="RawTherapee_(?:macOS|MacOS)_"#

    // History: docs/app-audits/com-rawtherapee-rawtherapee5.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-rawtherapee-rawtherapee5",
        probes: [stable(legacyID), stable(currentID)],
        changelogs: [notes(legacyID), notes(currentID)])

    private static func stable(_ id: String) -> VendorProbeRecipe {
        // The version and Apple Silicon minimum come from the same Universal
        // package link. The directory is alphabetical, not version-ordered.
        VendorProbeRecipe(
            bundleID: id,
            url: archives,
            mode: .hostCompatibleEntries(releasePageBase: downloads),
            versionPattern: #"\#(link)\#(number)_Universal_(\#(number))\.zip">"#,
            minimumSystemVersionPattern: #"\#(link)(\#(number))_Universal_\#(number)\.zip">"#,
            entryStartPattern: link,
            hostRequirement: .init(architectures: [.arm64]),
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
            excludedChannels: [.nightly],
            sourceTemplate: "https://rawtherapee.com/downloads/{version}/",
            headingPattern: #"<h2\b[^>]*>\s*<a\b[^>]*\baria-label="Permalink to (?<heading>[^"]+)""#)
    }
}
