import Foundation

enum im_riot_app {
    static let set = AppRecipeSet(
        family: "im-riot-app",
        probes: [
        // Element — Stable + Nightly, split bundle ids (`im.riot.app` vs
        // `im.riot.nightly` — verified 2026-06-04 against a real Nightly bundle;
        // the earlier `io.element.nightly` guess never matched and the probe
        // silently missed). `currentRelease` is the latest version (semver for
        // Stable, a `YYYYMMDDNN` build stamp for Nightly). One-click: the same
        // releases.json nests the installer under `updateTo.url` — the
        // `Element[-| Nightly-]<ver>-universal-mac.zip` on packages.element.io. We
        // capture that absolute zip url directly (each channel from its own feed).
        VendorProbeRecipe(
            bundleID: "im.riot.app",
            url: URL(string: "https://packages.element.io/desktop/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://packages\.element\.io/[^"]+\.zip)""#),
                kind: .zip)),
        VendorProbeRecipe(
            bundleID: "im.riot.nightly",
            url: URL(string: "https://packages.element.io/nightly/update/macos/releases.json")!,
            mode: .responseBody,
            versionPattern: #""currentRelease"\s*:\s*"([^"]+)""#,
            downloadURL: URL(string: "https://element.io/download"),
            changelogURL: URL(string: "https://github.com/element-hq/element-desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://packages\.element\.io/[^"]+\.zip)""#),
                kind: .zip),
            channel: .nightly),
        ],
        channelProofs: [
        ChannelProofKey("im.riot.nightly", .nightly): .artifact(#"/nightly/"#),
        ])
}
