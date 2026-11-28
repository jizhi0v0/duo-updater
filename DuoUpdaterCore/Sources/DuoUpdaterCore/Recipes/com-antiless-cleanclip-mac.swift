import Foundation

enum com_antiless_cleanclip_mac {
    static let bundleID = "com.antiless.cleanclip.mac"
    private static let releaseNotes = URL(string: "https://cleanclip.cc/docs/changelog")!
    private static let version = #"[0-9]+\.[0-9]+\.[0-9]+"#
    private static let betaVersion = version + #"-beta\.[0-9]+"#
    private static let anchor = #"<a\b[^>]*\sclass="header-anchor"[^>]*>\s*#\s*</a>\s*"#
    private static let download = #"<a\b[^>]*\shref="https://cleanclip\.cc/releases/download/"#

    static func usesObsoleteAppcast(_ app: InstalledApp, feedURL: URL) -> Bool {
        // It publishes 2.4.7 as the Sparkle build while legacy copies report
        // numeric builds such as 10512. Use the official GitHub release tags.
        app.bundleID?.caseInsensitiveCompare(bundleID) == .orderedSame
            && !app.isMASApp && !app.isTestFlightApp
            && feedURL.absoluteString == "https://cleanclip.cc/appcast.xml"
    }

    // History: docs/app-audits/com-antiless-cleanclip-mac.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-antiless-cleanclip-mac",
        changelogs: [
            notes(channel: .stable, versionPattern: version, excluding: .beta),
            notes(channel: .beta, versionPattern: betaVersion, excluding: .stable),
        ],
        githubRules: [
            // The vendor's GitHub release tag matches CFBundleShortVersionString.
            // The versioned universal DMG is also what the website distributes.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "CleanClip", repo: "CleanClipApp",
                versionPattern: #"^(\#(version))$"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^CleanClip-\#(version)\.dmg$"#,
                installerKind: .dmg),
            // Both tracks use the same bundle ID. The beta's installed version
            // retains its suffix, and the beta rule never selects a stable DMG.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "CleanClip", repo: "CleanClipApp",
                usePrereleases: true,
                versionPattern: #"^(\#(betaVersion))$"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^CleanClip-\#(betaVersion)\.dmg$"#,
                installerKind: .dmg,
                channel: .beta),
        ],
        githubChannelProofs: [
            ChannelProofKey(bundleID, .beta): .artifact(#"/download/\#(betaVersion)/"#),
        ])

    private static func notes(
        channel: ReleaseChannel, versionPattern: String, excluding otherChannel: ReleaseChannel
    ) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: bundleID,
            source: releaseNotes,
            entryPattern: #"<h2\b[^>]*>\s*"# + anchor
                + #"(?<version>\#(versionPattern))\s*</h2>\s*<p>\s*Date:\s*(?<date>[^<]+)</p>"#
                + #"(?<body>.*?)(?=<h2\b|<footer\b|\z)"#,
            // A download link is often appended to the last bullet. Stop at the
            // link or a nested list and let the next match read each sub-item.
            itemPatterns: [
                #"<li\b[^>]*>\s*(?:<p\b[^>]*>\s*)?(?<item>(?:(?!</?li\b|</p>|<[ou]l\b|\#(download)).)+?)(?=</li>|</p>|<[ou]l\b|\#(download))"#,
            ],
            channel: channel,
            excludedChannels: [otherChannel],
            headingPattern: #"<h3\b[^>]*>\s*"# + anchor + #"(?<heading>.*?)</h3>"#)
    }
}
