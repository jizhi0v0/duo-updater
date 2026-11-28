import Foundation

enum net_xmind_vana_app {
    static let bundleID = "net.xmind.vana.app"
    private static let version = #"[0-9]+(?:\.[0-9]+){2}"#
    static let betaVersion = version + "-beta"
    private static let artifactSuffix = #"-[0-9]{12}\.dmg\z"#
    private static let releases = URL(string: "https://xmind.com/changelog")!

    static let set = AppRecipeSet(
        family: "net-xmind-vana-app",
        probes: [
            // History: docs/app-audits/net-xmind-vana-app.md#历史与实测
            probe(url: URL(string: "https://xmind.app/zen/download/mac/")!,
                  channel: .stable, version: version, changelogURL: releases),
            probe(url: URL(string: "https://xmind.app/desktop-beta/download/mac/")!,
                  channel: .beta, version: betaVersion),
        ],
        changelogs: [
            // The Desktop cards put each labeled date and Xmind version next
            // to a rich text container. Read that container alone so unrelated
            // lists and the next version's notes do not fill gaps in this one.
            ChangelogRecipe(
                bundleID: bundleID,
                source: releases,
                entryPattern: #"<div\b[^>]*\bdata-framer-name="Publish date"[^>]*>\s*<p\b[^>]*>\s*(?<date>[^<]+?)\s*</p>"#
                    + #"(?:\s*</div>){1,3}\s*<div\b[^>]*>\s*<h2\b[^>]*>\s*Xmind\s+(?<version>\#(version))\s*</h2>"#
                    + #"(?:\s*</div>){1,4}\s*<div\b[^>]*\bdata-framer-component-type="RichTextContainer"[^>]*>(?<body>.*?)</div>"#,
                itemPatterns: [#"<li\b[^>]*>(?<item>.*?)</li>"#],
                channel: .stable,
                excludedChannels: [.beta],
                headingPattern: #"<h3\b[^>]*>(?<heading>.*?)</h3>"#),
            // The native beta manifest publishes the current release's numbered
            // notes in a JSON string. Its version carries the same beta suffix
            // as the installed copy and the public beta installer.
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://www.xmind.app/xmind/update/beta-latest-mac.json")!,
                entryPattern: #"\A\s*\{\s*"version"\s*:\s*"(?<version>\#(betaVersion))"\s*,.*?"releaseNotes"\s*:\s*"(?<body>(?:[^"\\]|\\.)*)""#,
                itemPatterns: [#"(?:\A|\\n)\s*[0-9]+\.\s*(?<item>.*?)(?=\\n|\z)"#],
                mode: .json,
                maxEntries: 1,
                channel: .beta,
                excludedChannels: [.stable]),
        ],
        channelProofs: [
            ChannelProofKey(bundleID, .beta): .artifact("-beta" + artifactSuffix),
        ],
        oneClickGates: [
            // Xmind also distributes separately licensed enterprise packages.
            // The public stable and beta builds both declare this release type.
            OneClickGate(
                bundleID: bundleID,
                requirement: .asarEntry(
                    path: "package.json",
                    pattern: #"(?<=[,{])\s*"releaseType"\s*:\s*"vana_macosx"\s*[,}]"#),
                reason: "the installed copy does not declare Xmind's public macOS edition; update it from its own distribution"),
        ])

    private static func probe(
        url: URL, channel: ReleaseChannel, version: String, changelogURL: URL? = nil
    ) -> VendorProbeRecipe {
        // The public downloads return versioned DMGs in Location. The date
        // suffix identifies the archive, while the preceding version matches
        // CFBundleShortVersionString. Keep the complete Location so detection
        // and install refer to the same release.
        VendorProbeRecipe(
            bundleID: bundleID,
            url: url,
            mode: .redirectFilename,
            versionPattern: #"\Ahttps://dl3\.xmind\.app/Xmind-for-macOS-(\#(version))"# + artifactSuffix,
            downloadURL: url,
            changelogURL: changelogURL,
            install: VendorInstallSpec(urlSource: .bodyPattern(#"\A(.+)\z"#), kind: .dmg),
            followRedirects: false,
            channel: channel,
            installedVersionPattern: #"\A\#(version)\z"#)
    }
}
