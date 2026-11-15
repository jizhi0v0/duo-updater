import Foundation

enum org_whispersystems_signal_desktop {
    static let set = AppRecipeSet(
        family: "org-whispersystems-signal-desktop",
        probes: [
        // History: docs/app-audits/org-whispersystems-signal-desktop.md#历史与实测
        // Signal Stable + Beta have separate ids and electron-builder feeds.
        // Select the arm64 ZIP and its SHA512 from the SAME files entry: the
        // top-level path/hash belongs to x64. Each channel has its own filename.
        // Signal staples DMGs after hashing them; the ZIP digest describes the
        // served archive. VendorInstaller still checks Developer ID, Team and id.
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            url: URL(string: "https://updates.signal.org/desktop/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-mac-arm64-[^\s]+\.zip)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .zip,
                checksumPattern: #"signal-desktop-mac-arm64-[^\n]+\.zip\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            url: URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-beta-mac-arm64-[^\s]+\.zip)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .zip,
                checksumPattern: #"signal-desktop-beta-mac-arm64-[^\n]+\.zip\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#),
            channel: .beta),
        ],
        changelogs: [
        // History: docs/app-audits/org-whispersystems-signal-desktop.md#历史与实测
        // Signal Stable + Beta — GitHub releases of signalapp/Signal-Desktop, the
        // page both probes link. One repo, one tag scheme: stable is `v8.30.0`,
        // beta is `v8.31.0-beta.1`, and GitHub's `prerelease` bit is set on exactly
        // the `-beta.N` tags. With the leading `v` stripped, each tag is the
        // version its channel's yml offers, so no `tagPattern` is needed.
        //
        // The notes are thin: one to three bullets of prose per release, often the
        // stock "Small tweaks, bug fixes, and performance enhancements" line, and
        // a beta's body is usually copied unchanged into the stable release that
        // follows it.
        //
        // The beta recipe reads prereleases only (`channel: .beta`) and does NOT
        // set `includesPromotedStable`: Signal Beta is a separate app whose feed
        // and artifact (`signal-desktop-beta-mac-universal-<ver>-beta.N.dmg`) are
        // always a `-beta.N` build, so a stable entry would describe a build this
        // install is never offered.
        ChangelogRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            source: URL(string: "https://api.github.com/repos/signalapp/Signal-Desktop/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            source: URL(string: "https://api.github.com/repos/signalapp/Signal-Desktop/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            structuredFormat: .gitHubReleases),
        ],
        channelProofs: [
        ChannelProofKey("org.whispersystems.signal-desktop-beta", .beta): .artifact(#"signal-desktop-beta-mac-"#),
        ])
}
