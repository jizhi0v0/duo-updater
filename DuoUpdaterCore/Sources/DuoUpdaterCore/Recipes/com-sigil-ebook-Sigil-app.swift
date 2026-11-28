import Foundation

enum com_sigil_ebook_Sigil_app {
    private static let bundleID = "com.sigil-ebook.Sigil.app"
    private static let downloads = URL(string: "https://sigil-ebook.com/sigil/download/")!
    private static let history = URL(string: "https://raw.githubusercontent.com/Sigil-Ebook/Sigil/master/ChangeLog.txt")!
    private static let version = #"[0-9]+(?:\.[0-9]+){2}"#
    private static let releaseHeading = #"^Sigil(?:-[ \t]*|[ \t]+)"#

    // History: docs/app-audits/com-sigil-ebook-Sigil-app.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-sigil-ebook-Sigil-app",
        probes: [
            // Match the current ARM download button, where the tag and filename
            // must agree. The source tags can be ahead of the macOS package.
            VendorProbeRecipe(
                bundleID: bundleID,
                url: downloads,
                mode: .responseBody,
                versionPattern:
                    #"<a\b[^>]*\shref="https://github\.com/Sigil-Ebook/Sigil/releases/download/(\#(version))/Sigil\.app-\1-Mac-arm64\.txz"[^>]*>"#
                    + #"\s*Latest\s+MacOS\s+\(Arm64\)\s+download\s*</a>"#,
                downloadURL: downloads,
                changelogURL: history,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate(
                        "https://github.com/Sigil-Ebook/Sigil/releases/download/{version}/Sigil.app-{version}-Mac-arm64.txz"),
                    // libarchive detects the tar compression from its bytes.
                    kind: .tarGz),
                hostRequirement: .init(architectures: [.arm64])),
        ],
        changelogs: [
            // The vendor's plain-text log wraps a bullet onto more deeply
            // indented lines. Pre-release headings terminate a stable entry.
            ChangelogRecipe(
                bundleID: bundleID,
                source: history,
                entryPattern: #"(?m)\#(releaseHeading)(?<version>\#(version))[ \t]*\r?\n"#
                    + #"(?<body>.*?)(?=\#(releaseHeading)[0-9]|^pre-\#(version)|\z)"#,
                itemPatterns: [#"(?m)^[ \t]+-[ \t]+(?<item>[^\r\n]+(?:\r?\n {7,}(?![-*][ \t])[^ \r\n][^\r\n]*)*)"#],
                stripTags: false,
                decodeEntities: false,
                headingPattern: #"(?m)^[ \t]+(?<heading>Bug Fixes|New Features):?[ \t]*\r?$"#),
        ])
}
