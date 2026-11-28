import Foundation

enum org_mixxx_mixxx {
    private static let downloads = URL(string: "https://mixxx.org/download/")!
    private static let notes = URL(string: "https://manual.mixxx.org/latest/en/chapters/appendix/changelog")!
    private static let armButton = #"<a\s+class="button button-primary package-macosarm"\s+href=""#
    private static let releaseDirectory = #"https://downloads\.mixxx\.org/releases/"#
    private static let version = #"[0-9]+\.[0-9]+\.[0-9]+"#

    static let set = AppRecipeSet(
        family: "org-mixxx-mixxx",
        probes: [
            // History: docs/app-audits/org-mixxx-mixxx.md#历史与实测
            // Use the ARM release button, and require the same version in both
            // the directory and filename. Snapshot buttons use /snapshots/.
            VendorProbeRecipe(
                bundleID: MixxxBuild.bundleID,
                url: downloads,
                mode: .responseBody,
                versionPattern: #"\A\#(armButton)\#(releaseDirectory)(\#(version))/mixxx-\1-macosarm\.dmg""#,
                downloadURL: downloads,
                changelogURL: notes,
                entryStartPattern: armButton,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate(
                        "https://downloads.mixxx.org/releases/{version}/mixxx-{version}-macosarm.dmg"),
                    kind: .dmg,
                    checksumPattern: #"\A\#(armButton)[^"]+"[^>]*>[^<]*</a>\s*<ul class="download-meta">"#
                        + #"(?:(?!</ul>)[\s\S])*?<li title="([0-9a-f]{64})">\s*"#
                        + #"<img[^>]*alt="SHA256 Checksum"[^>]*>\s*<a href="\#(releaseDirectory)\#(version)/mixxx-\#(version)-macosarm\.dmg\.sha256sum""#,
                    checksumFormat: .sha256Hex),
                hostRequirement: .init(architectures: [.arm64]),
                installedVersionPattern: #"\A\#(version)\z"#),
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
                headingPattern: #"<h3>(?<heading>[^<]+)<a\b[^>]*class="headerlink""#),
        ])
}
