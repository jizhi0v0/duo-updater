import Foundation

enum com_code_athas {
    private static let archive = "https://github.com/athasdev/athas/releases/download/v{version}/Athas_aarch64.app.tar.gz"
    private static let releases = URL(string: "https://github.com/athasdev/athas/releases")!
    private static let releaseAPI = URL(string: "https://api.github.com/repos/athasdev/athas/releases?per_page=40")!
    private static let channels: [ReleaseChannel] = [.stable, .beta]

    static let set = AppRecipeSet(
        family: "com-code-athas",
        probes: channels.map { channel in
            // History: docs/app-audits/com-code-athas.md#历史与实测
            // Both updaters read this manifest. Beta also receives stable
            // releases when they are newest. Require the matching arm64 archive.
            let version = #"[0-9]+\.[0-9]+\.[0-9]+"# + (channel == .beta ? #"(?:-beta\.[0-9]+)?"# : "")
            return VendorProbeRecipe(
                bundleID: AthasChannel.bundleID,
                url: URL(string: "https://athas.dev/api/update/stable")!,
                mode: .responseBody,
                versionPattern:
                    #""version"\s*:\s*"(\#(version))"(?=[\s\S]*"darwin-aarch64"\s*:\s*\{[^{}]*"url"\s*:\s*"https://github\.com/athasdev/athas/releases/download/v\1/Athas_aarch64\.app\.tar\.gz")"#,
                downloadURL: URL(string: "https://athas.dev/download"),
                changelogURL: releases,
                publishedAtPattern: #""pub_date"\s*:\s*"([^"]+)""#,
                install: VendorInstallSpec(urlSource: .versionTemplate(archive), kind: .tarGz),
                requestHeaders: ["X-Athas-Update-Channel": channel.rawValue],
                channel: channel,
                hostRequirement: VendorHostRequirement(architectures: [.arm64]))
        },
        changelogs: channels.map { channel in
            ChangelogRecipe(
                bundleID: AthasChannel.bundleID, source: releaseAPI, mode: .json, maxEntries: 15,
                channel: channel, includesPromotedStable: channel == .beta,
                structuredFormat: .gitHubReleases,
                tagPattern: channel == .beta
                    ? #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$"#
                    : #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#)
        },
        channelProofs: [
            ChannelProofKey(AthasChannel.bundleID, .beta):
                .recipeAnchor(#"\AX-Athas-Update-Channel\nbeta\z"#, in: ["requestHeaders"]),
        ])
}
