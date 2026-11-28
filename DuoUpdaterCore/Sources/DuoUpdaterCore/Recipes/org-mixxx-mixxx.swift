import Foundation

enum org_mixxx_mixxx {
    private static let downloads = URL(string: "https://mixxx.org/download/")!
    private static let notes = URL(string: "https://manual.mixxx.org/latest/en/chapters/appendix/changelog")!
    private static let armButton = #"<a\s+class="button button-primary package-macosarm"\s+href=""#
    private static let releaseDirectory = #"https://downloads\.mixxx\.org/releases/"#
    private static let version = #"[0-9]+\.[0-9]+\.[0-9]+"#
    private static let archive = #"macosarm\.dmg"#
    private static let checksum = #"[0-9a-f]{64}"#
    private static let checksumTitle = #"<li title=""#
    private static let checksumLink = #""\s*>\s*<img[^>]*alt="SHA256 Checksum"[^>]*>\s*<a href=""#
    private static let cardMetadata = #"[^>]*>[^<]*</a>\s*<ul class="download-meta">"#
        + #"(?:(?!</ul>|\#(checksumTitle)\#(checksum)")[\s\S])*"#

    // History: docs/app-audits/org-mixxx-mixxx.md#历史与实测
    // The ARM button and its adjacent digest link must name the same release.
    private static let releasePattern = #"\A\#(armButton)\#(releaseDirectory)(\#(version))/mixxx-\1-\#(archive)""#
        + cardMetadata + checksumTitle + checksum + checksumLink
        + #"\#(releaseDirectory)\1/mixxx-\1-\#(archive)\.sha256sum""#

    static let set = AppRecipeSet(
        family: "org-mixxx-mixxx",
        probes: [
            VendorProbeRecipe(
                bundleID: MixxxBuild.bundleID,
                url: downloads,
                mode: .responseBody,
                versionPattern: releasePattern,
                downloadURL: downloads,
                changelogURL: notes,
                entryStartPattern: armButton,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate(
                        "https://downloads.mixxx.org/releases/{version}/mixxx-{version}-macosarm.dmg"),
                    kind: .dmg,
                    checksumPattern: #"\A\#(armButton)[^"]+""# + cardMetadata + checksumTitle
                        + "(\(checksum))" + checksumLink
                        + #"\#(releaseDirectory)\#(version)/mixxx-\#(version)-\#(archive)\.sha256sum""#,
                    checksumFormat: .sha256Hex),
                variant: "arm64",
                hostRequirement: .init(architectures: [.arm64]),
                installedVersionPattern: #"\A(?!(?:\#(MixxxBuild.legacyVersionAlternatives))\z)\#(version)\z"#),
            // The old official Intel packages were signed by a different Team.
            // They still need a version and a link to the official download page.
            VendorProbeRecipe(
                bundleID: MixxxBuild.bundleID,
                url: downloads,
                mode: .responseBody,
                versionPattern: releasePattern,
                downloadURL: downloads,
                changelogURL: notes,
                entryStartPattern: armButton,
                variant: "legacy-intel",
                hostRequirement: .init(architectures: [.arm64]),
                installedVersionPattern: #"\A(?:\#(MixxxBuild.legacyVersionAlternatives))\z"#),
        ],
        changelogs: [
            // The current manual contains unreleased and skipped headings too.
            // Only dated entries are releases, and every H2 ends a release.
            ChangelogRecipe(
                bundleID: MixxxBuild.bundleID,
                source: notes,
                entryPattern: #"<h2>\s*<a\b[^>]*>(?<version>\#(version))</a>\s*\((?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\)<a\b[^>]*>[^<]*</a>\s*</h2>"#
                    + #"(?<body>.*?)(?=<h2\b|\z)"#,
                itemPatterns: [#"<li><p>(?<item>.*?)</p></li>"#],
                channel: .stable,
                excludedChannels: [.beta, .alpha, .nightly],
                headingPattern: #"<h3>(?<heading>[^<]+)<a\b[^>]*class="headerlink""#),
        ])
}
