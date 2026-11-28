import Foundation

enum com_gitbutler_app {
    private static let bundleID = "com.gitbutler.app"
    private static let history = URL(string: "https://gitbutler.com/downloads")!

    // History: docs/app-audits/com-gitbutler-app.md#历史与实测
    // The Tauri endpoint returns a single flat object. Match only top-level
    // fields, and require the release version and native archive URL to agree.
    private static let jsonString = #""(?:[^"\\]|\\.)*""#
    private static let manifest = #"\A\s*\{\s*"#
    private static let field = #"\#(jsonString)\s*:\s*\#(jsonString)\s*,\s*"#
    private static let beforeVersion = #"(?:(?!"version"\s*:)\#(field))*"#
    private static let beforeURL = #"(?:(?!"url"\s*:)\#(field))*"#
    private static let version = #"[0-9]+(?:\.[0-9]+){2}"#
    private static let archivePrefix = #"https://releases\.gitbutler\.com/releases/release/"#
    private static let archiveSuffix = #"-[0-9]+/macos/aarch64/GitButler\.app\.tar\.gz"#
    private static let urlField = #"\#(beforeURL)"url"\s*:\s*""#
    private static let fieldEnd = #""(?=\s*[,}])"#

    static let set = AppRecipeSet(
        family: "com-gitbutler-app",
        probes: [
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: "https://app.gitbutler.com/releases/release/darwin-aarch64/0.0.0")!,
                mode: .responseBody,
                versionPattern: manifest
                    + #"(?=\#(beforeVersion)"version"\s*:\s*"(\#(version))\#(fieldEnd))"#
                    + urlField + archivePrefix + #"\1"# + archiveSuffix + fieldEnd,
                downloadURL: history,
                changelogURL: history,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(
                        manifest + urlField + "(" + archivePrefix + version + archiveSuffix + ")" + fieldEnd),
                    kind: .tarGz),
                hostRequirement: .init(architectures: [.arm64])),
        ],
        changelogs: [
            // The download page has a latest-release hero followed by stable
            // version cards. Both carry a date and a release-notes-content block.
            ChangelogRecipe(
                bundleID: bundleID,
                source: history,
                entryPattern:
                    #"(?:<div class="latest-release__header-subtitle\b[^"]*"><span[^>]*>|<h3 class="release-version\b[^"]*">)"#
                    + #"(?<version>[0-9]+(?:\.[0-9]+){2})(?: Latest release</span>\s*<span[^>]*>•</span>|</h3>)\s*"#
                    + #"<span[^>]*>(?<date>[0-9]{1,2} [A-Za-z]+ [0-9]{4})</span>"#
                    + #"(?:(?!</section>|<h3 class="release-version\b).)*?<div class="release-notes-content\b[^"]*">(?<body>.*?)</div>"#,
                itemPatterns: [#"<(li|p)\b[^>]*>(?<item>.*?)</\1>"#],
                headingPattern: #"<h2\b[^>]*>(?<heading>.*?)</h2>"#),
        ])
}
