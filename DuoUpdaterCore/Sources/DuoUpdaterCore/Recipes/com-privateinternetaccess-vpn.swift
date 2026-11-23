import Foundation

enum com_privateinternetaccess_vpn {
    private static let bundleID = PrivateInternetAccessChannel.bundleID
    private static let changelog = URL(string: "https://www.privateinternetaccess.com/pages/changelog")!
    private static let betaFeed = URL(string: "https://www.privateinternetaccess.com/clients/desktop/beta.json")!

    static let set = AppRecipeSet(
        family: "com-privateinternetaccess-vpn",
        // History: docs/app-audits/com-privateinternetaccess-vpn.md#历史与实测
        // PIA checks GA even with Receive Beta Updates enabled. The special
        // beta feed can win version detection, while only the release page
        // publishes a Mac archive with a usable SHA-256.
        probes: [
            stableRecipe(channel: .stable),
            stableRecipe(channel: .beta),
            VendorProbeRecipe(
                bundleID: bundleID, url: betaFeed, mode: .responseBody,
                versionPattern: #""latest_version_piax"\s*:\s*\{(?:\s*"[^"]+"\s*:\s*\{[^{}]*\}\s*,)*\s*"mac"\s*:\s*\{[^{}]*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+)+-beta(?:\.[0-9]+)?)(?:\+[0-9]+)?""#,
                downloadURL: URL(string: "https://helpdesk.privateinternetaccess.com/hc/en-us/articles/46777259429531-macOS-Installing-and-Using-the-PIA-App"),
                changelogURL: changelog,
                channel: .beta,
                variant: "beta-feed"),
        ],
        changelogs: [
            // PIA's stable page lists one release per article: h3 version,
            // release date and bullet notes. Downloads precede the version,
            // while SHA-256 paragraphs follow the notes. Keep the article
            // boundary so an empty release cannot borrow the next one's notes.
            // Beta shares this GA history; it has no beta-only notes here.
            ChangelogRecipe(
                bundleID: bundleID,
                source: changelog,
                entryPattern:
                    #"<article class="changelog-release">"#
                    + #"(?:(?!</?article\b).)*?<h3\b[^>]*>\s*v(?<version>[0-9]+(?:\.[0-9]+)+)\s*</h3>"#
                    + #"(?:(?!</?article\b|Release Date:|<ul\b).)*"#
                    + #"(?:Release Date:\s*(?<date>[A-Za-z]+\s+[0-9]{1,2},\s+[0-9]{4}))?"#
                    + #"(?<body>(?:(?!</?article\b).)*)</article>"#,
                itemPatterns: [
                    #"<li\b[^>]*>(?<item>.*?)</li>"#,
                ]),
        ],
        channelProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"/(?:pages/changelog|clients/desktop/beta\.json)$"#, in: ["url"]),
        ])

    private static func stableRecipe(channel: ReleaseChannel) -> VendorProbeRecipe {
        let macFilename = #"pia-macos-[0-9]+(?:\.[0-9]+)+-[0-9]+\.zip"#
        return VendorProbeRecipe(
            bundleID: bundleID, url: changelog, mode: .responseBody,
            versionPattern: #"<h3\b[^>]*>\s*v([0-9]+(?:\.[0-9]+)+)\s*</h3>"#,
            downloadURL: changelog,
            changelogURL: changelog,
            entryStartPattern: #"<article class="changelog-release">"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"href="(https://installers\.privateinternetaccess\.com/download/\#(macFilename))""#),
                kind: .zip,
                checksumPattern: #"<p class="sha256">\s*\#(macFilename)\s*:\s*<span class="code">([a-fA-F0-9]{64})</span>"#,
                checksumFormat: .sha256Hex,
                installerApp: VendorInstallerApp(
                    bundleIdentifier: bundleID,
                    teamIdentifier: "5357M5NW9W",
                    installedPath: "/Applications/Private Internet Access.app")),
            channel: channel,
            variant: channel == .beta ? "ga-fallback" : nil)
    }
}
