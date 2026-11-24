import Foundation

enum com_electron_ollama {
    private static let bundleID = OllamaUpdateChannel.bundleID
    private static let releases = URL(string: "https://github.com/ollama/ollama/releases")!
    private static let archivePrefix = #"https://github\.com/ollama/ollama/releases/download/v"#
    private static let releaseVersion = #"[0-9]+(?:\.[0-9]+)+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"#
    private static let archiveSuffix = #"/Ollama-darwin\.zip"#

    static let set = AppRecipeSet(
        family: "com-electron-ollama",
        probes: [
            // History: docs/app-audits/com-electron-ollama.md#历史与实测
            // Ollama's desktop updater asks its own API about the running version.
            // The service decides whether to offer a release. Take both the full
            // version (including any suffix) and ZIP URL from that same answer.
            // The ZIP is installed through the normal Developer ID checks.
            updateProbe(channel: .stable),
            updateProbe(channel: .preview),
        ],
        changelogs: [
        // History: docs/app-audits/com-electron-ollama.md#历史与实测
        // Ollama — GitHub releases page. Each release is a <section> with an
        // sr-only h2 (version tag, e.g. "v0.30.0"), a <relative-time> element
        // (ISO datetime), and a <div class="markdown-body …"> with the release
        // body. The version group strips the leading "v" by not capturing it.
        // Only <h2> values matching v+digits are captured so nav sections skip.
        //
        // Most releases are a bullet list, but some are written as prose with no
        // <li> at all. An entry that yields no items is dropped, so without the
        // paragraph fallback such a release vanishes from the pane (#507). Item
        // patterns are tried in order and the first that yields
        // anything wins, so the paragraph fallback only ever speaks for a release
        // with no bullets. It skips the "Full Changelog: vA...vB" compare-link line,
        // which would otherwise be a prose release's last item.
        //
        // Pre-releases are skipped: the h2 is the release NAME, not the tag, and
        // Ollama names its release candidates after the version they lead up to
        // (e.g. tag `v0.40.0-rc3` carries the h2 `v0.40.0`), so `[\d.]+` reads an
        // rc as a final release. The structured history therefore selects
        // the stable releases (#872). The section's
        // "Pre-release" label sits between the h2 and `<relative-time>`; the
        // tempered dot refuses to step over it. The label, not the tag's shape, is
        // the discriminator: a prerelease can carry a plain `v<x.y.z>` tag (History).
        ChangelogRecipe(
            bundleID: bundleID,
            source: releases,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>v(?<version>[\d.]+)</h2>(?:(?!>Pre-release<).)*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [
                #"<li>(?<item>.*?)</li>"#,
                #"<p>(?!<strong>Full Changelog</strong>)(?<item>.*?)</p>"#,
            ]),
        // Preview can also be served a promoted stable release. Use the actual
        // tag from the release section so a candidate keeps its exact suffix.
        ChangelogRecipe(
            bundleID: bundleID,
            source: releases,
            entryPattern: #"<section[^>]*\bid="release-v(?<version>\#(releaseVersion))"[^>]*>"#
                + #"(?:(?!</section>).)*?<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [
                #"<li>(?<item>.*?)</li>"#,
                #"<p>(?!<strong>Full Changelog</strong>)(?<item>.*?)</p>"#,
            ],
            channel: .preview),
        ],
        channelProofs: [
            ChannelProofKey(bundleID, .preview):
                .recipeAnchor(#"[?&]channel=preview(?:&|\z)"#, in: ["url"]),
        ],
        changelogPages: [bundleID: releases])

    private static func updateProbe(channel: ReleaseChannel) -> VendorProbeRecipe {
        let preview = channel == .preview
        let endpoint = "https://ollama.com/api/update?os=darwin&arch=arm64"
            + (preview ? "&channel=preview" : "")
        return VendorProbeRecipe(
            bundleID: bundleID,
            url: URL(string: endpoint)!,
            mode: .installedVersionResponseBody(queryParameter: "version"),
            versionPattern: #""url"\s*:\s*"\#(archivePrefix)(\#(releaseVersion))\#(archiveSuffix)""#,
            downloadURL: URL(string: preview
                ? "https://docs.ollama.com/faq#how-do-i-install-a-pre-release"
                : "https://ollama.com/download"),
            changelogURL: releases,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(\#(archivePrefix)\#(releaseVersion)\#(archiveSuffix))""#),
                kind: .zip),
            channel: channel)
    }
}
