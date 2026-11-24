import Foundation

enum com_electron_ollama {
    static let bundleID = "com.electron.ollama"
    private static let releases = URL(string: "https://github.com/ollama/ollama/releases")!
    private static let archivePrefix = "https://github.com/ollama/ollama/releases/download/v"
    private static let stableVersion = #"[0-9]+(?:\.[0-9]+)+"#
    private static let releaseVersion = stableVersion + #"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"#
    private static let archiveSuffix = "/Ollama-darwin.zip"

    static let set = AppRecipeSet(
        family: "com-electron-ollama",
        probes: [
            // History: docs/app-audits/com-electron-ollama.md#历史与实测
            // Ollama's desktop updater asks its own API about the running version.
            // The service decides whether to offer a release. Take both the full
            // version (including any suffix) and ZIP URL from that same answer.
            // The ZIP is installed through the normal Developer ID checks.
            updateProbe(channel: .stable),
            // Ollama documents Preview for manual installation. Verify that
            // feed separately while its desktop updater has no channel setting.
            updateProbe(channel: .preview),
        ],
        changelogs: [releaseNotes(channel: .stable), releaseNotes(channel: .preview)],
        channelProofs: [
            ChannelProofKey(bundleID, .preview):
                .recipeAnchor(#"[?&]channel=preview(?:&|\z)"#, in: ["url"]),
        ],
        changelogPages: [bundleID: releases])

    private static func releaseNotes(channel: ReleaseChannel) -> ChangelogRecipe {
        let preview = channel == .preview
        // GitHub's release title can name the final version while the tag
        // still carries an RC suffix. Plain tags can also be marked prerelease.
        let tag = preview ? releaseVersion : stableVersion
        let metadata = preview ? #"(?:(?!</section>).)*?"# : #"(?:(?!</section>|>Pre-release<).)*?"#
        return ChangelogRecipe(
            bundleID: bundleID,
            source: releases,
            entryPattern: #"<section[^>]*\bid="release-v(?<version>\#(tag))"[^>]*>"#
                + metadata + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>"#
                + #"(?:(?!</section>).)*?<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            // Prose-only releases use paragraphs after list items are tried.
            itemPatterns: [
                #"<li>(?<item>.*?)</li>"#,
                #"<p>(?!<strong>Full Changelog</strong>)(?<item>.*?)</p>"#,
            ],
            channel: preview ? .preview : nil)
    }

    private static func updateProbe(channel: ReleaseChannel) -> VendorProbeRecipe {
        let preview = channel == .preview
        let endpoint = "https://ollama.com/api/update?os=darwin&arch=arm64"
            + (preview ? "&channel=preview" : "")
        let prefixPattern = NSRegularExpression.escapedPattern(for: archivePrefix)
        let suffixPattern = NSRegularExpression.escapedPattern(for: archiveSuffix)
        return VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: endpoint)!,
            mode: .installedVersionJSONURL(queryParameter: "version"),
            versionPattern: #"\A\#(prefixPattern)(\#(releaseVersion))\#(suffixPattern)\z"#,
            downloadURL: URL(string: preview
                ? "https://docs.ollama.com/faq#how-do-i-install-a-pre-release"
                : "https://ollama.com/download"),
            changelogURL: releases,
            install: VendorInstallSpec(
                urlSource: .versionTemplate("\(archivePrefix){version}\(archiveSuffix)"),
                kind: .zip),
            channel: channel)
    }
}
