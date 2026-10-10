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
            changelogURL: URL(string: "https://github.com/element-hq/element-web/releases"),
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
        changelogs: [
        // History: docs/app-audits/im-riot-app.md#历史与实测
        // Element Stable — GitHub releases of element-hq/element-web. The desktop
        // app's own repo (element-hq/element-desktop) is archived; desktop releases
        // are now cut from element-web, whose `v<X.Y.Z>` tags carry the same
        // version `currentRelease` offers, with the desktop-relevant notes in the
        // same body.
        //
        // `tagPattern` is required, not decoration: the same Releases list also
        // publishes the module packages (`module/banner/v2.1.1`,
        // `module/widget-toggles/v1.1.0`, …) as NON-prerelease releases, so the
        // stable filter alone would render them as Element entries. Release
        // candidates (`v1.12.31-rc.1`) are prereleases and are dropped by the
        // stable filter; the `$` anchor rejects them too.
        //
        // No recipe for `im.riot.nightly`: its `YYYYMMDDNN` build stamps have no
        // tag or release of their own here, so nothing could match its version.
        ChangelogRecipe(
            bundleID: "im.riot.app",
            source: URL(string: "https://api.github.com/repos/element-hq/element-web/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#),
        ],
        channelProofs: [
        ChannelProofKey("im.riot.nightly", .nightly): .artifact(#"/nightly/"#),
        ])
}
