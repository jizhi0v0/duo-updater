import Foundation

enum anomaly_opencode_rune {
    private static let bundleID = "anomaly.opencode-rune"
    private static let version = #"[0-9]+\.[0-9]+\.[0-9]+-dev-[0-9]+"#
    private static let release = #""release"\s*:\s*\{"#
    private static let armDMG = #""macos-arm64-dmg"\s*:\s*\{"#
    private static let sha256 = #""sha256"\s*:\s*"[0-9a-f]{64}""#

    static let set = AppRecipeSet(
        family: "anomaly-opencode-rune",
        probes: [
        // The native desktop client's public dev manifest is published before
        // its GitHub mirror. The numbered dev suffix is in the installed short
        // version and already selects .dev. Local and PR builds use other IDs.
        // Wait for the public rollout to reach 100%; Duo does not bucket devices
        // the way the built-in updater does.
        // History: docs/app-audits/anomaly-opencode-rune.md#历史与实测
        VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: "https://anoma.ly/release/opencode/desktop-rune/dev.json")!,
            mode: .responseBody,
            versionPattern: release
                + #"(?=[^{}]*"rollout_percent"\s*:\s*100\s*[,}])[^{}]*?"version"\s*:\s*"(\#(version))""#,
            trackClosedPattern: release + #"[^{}]*?"rollout_percent"\s*:\s*[0-9]{1,2}\s*[,}]"#,
            downloadURL: URL(string: "https://github.com/anomalyco/opencode-rune/blob/dev/docs/trying-opencode-rune.md")!,
            changelogURL: URL(string: "https://github.com/anomalyco/opencode-rune/releases")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    armDMG + #"(?=[^{}]*\#(sha256))[^{}]*?"url"\s*:\s*"(/release/opencode/files/[0-9a-f]{64}/OpenCode-Rune-\#(version)-macos-arm64\.dmg)""#,
                    base: URL(string: "https://anoma.ly")!),
                kind: .dmg,
                checksumPattern: armDMG + #"[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            channel: .dev,
            hostRequirement: VendorHostRequirement(architectures: [.arm64]),
            installedVersionPattern: #"^\#(version)$"#),
        ],
        changelogs: [
        // The GitHub mirror marks dev releases as ordinary releases. The
        // anchored dev tag picks the desktop train without relying on the flag
        // to identify it.
        ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://api.github.com/repos/anomalyco/opencode-rune/releases?per_page=20")!,
            mode: .json,
            maxEntries: 15,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v(\#(version))$"#),
        ],
        channelProofs: [
        ChannelProofKey(bundleID, .dev):
            .artifact(#"/OpenCode-Rune-[0-9.]+-dev-[0-9]+-macos-arm64\.dmg$"#),
        ])
}
