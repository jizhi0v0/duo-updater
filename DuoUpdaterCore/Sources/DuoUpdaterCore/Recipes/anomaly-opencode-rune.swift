import Foundation

enum anomaly_opencode_rune {
    private static let bundleID = "anomaly.opencode-rune"
    private static let version = #"[0-9]+\.[0-9]+\.[0-9]+-dev-[0-9]+"#

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
            mode: .opencodeRuneManifest,
            versionPattern: #""version"\s*:\s*"(\#(version))""#,
            downloadURL: URL(string: "https://github.com/anomalyco/opencode-rune/blob/dev/docs/trying-opencode-rune.md")!,
            changelogURL: URL(string: "https://github.com/anomalyco/opencode-rune/releases")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""url"\s*:\s*"([^"]+)""#,
                    base: URL(string: "https://anoma.ly")!),
                kind: .dmg,
                checksumPattern: #""sha256"\s*:\s*"([0-9a-f]{64})""#,
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

    // Project only the public dev release and its exact DMG. The URL is
    // immutable: both the SHA-256 and the release version occur in its path.
    // A missing or mismatched target still lets the probe detect the version.
    static func releaseBody(from body: String) -> (text: String, isTrackClosed: Bool)? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let manifest = try? decoder.decode(Manifest.self, from: Data(body.utf8)),
              manifest.schema == 1, manifest.app == "opencode",
              manifest.artifact == "desktop-rune", manifest.channel == "dev",
              manifest.release.version.range(of: #"\A\#(version)\z"#, options: .regularExpression) != nil,
              (0...100).contains(manifest.release.rolloutPercent)
        else { return nil }
        let release = manifest.release
        guard release.rolloutPercent == 100 else { return ("", true) }

        var projected = ["version": release.version]
        projected["published_at"] = manifest.publishedAt
        if let target = release.targets?.arm64DMG,
           target.sha256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil,
           target.url == "/release/opencode/files/\(target.sha256)/OpenCode-Rune-\(release.version)-macos-arm64.dmg" {
            projected["url"] = target.url
            projected["sha256"] = target.sha256
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: projected, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return (String(decoding: data, as: UTF8.self), false)
    }

    private struct Manifest: Decodable {
        let schema: Int
        let app: String
        let artifact: String
        let channel: String
        let publishedAt: String?
        let release: Release
    }

    private struct Release: Decodable {
        let version: String
        let rolloutPercent: Int
        let targets: Targets?
    }

    private struct Targets: Decodable {
        struct Target: Decodable {
            let url: String
            let sha256: String
        }

        let arm64DMG: Target?

        private enum CodingKeys: String, CodingKey {
            case arm64DMG = "macos-arm64-dmg"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            arm64DMG = try? container.decode(Target.self, forKey: .arm64DMG)
        }
    }
}
