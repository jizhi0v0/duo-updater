import Foundation

enum io_nekohasekai_screensharing {
    static let set = AppRecipeSet(
        family: "io-nekohasekai-screensharing",
        probes: [
        // Open Screen Sharing — the nightly track, for a copy whose Update Track
        // setting says nightly (`OpenScreenSharingChannel`, which needs Full Disk
        // Access; without it the copy stays on the stable rule below).
        //
        // Reads what the app's own updater reads for that track
        // (`UpdateChecker.swift`): the `nightly` release's `metadata.json`, and
        // offers it when `build` is above the installed `CFBundleVersion`. The
        // vendor's CI overwrites that release on every build (`build.yml`: the
        // build number is the previous nightly's + 1), and the marketing version
        // only moves on a "Bump" commit, so the build is the only order there is
        // — `versionIsBuild`, with the marketing version shown beside it.
        //
        // The pkg is the same release's `OpenScreenSharing.pkg`: one component pkg
        // with no scripts, `install-location="/Applications"`, Developer ID
        // Installer P8XK3KHB48 — the stable release is a byte copy of an earlier
        // nightly (`release.yml`). The two files are fetched separately, so a
        // build landing in between installs the newer nightly; the Team-ID gate
        // still applies, and the next check reads its build.
        //
        // Reads the newest build on the track: the one the app itself offers a
        // nightly user, from a public download link the README gives.
        VendorProbeRecipe(
            bundleID: "io.nekohasekai.screensharing",
            url: URL(string: "https://github.com/nekohasekai/open-screen-sharing/releases/download/nightly/metadata.json")!,
            mode: .responseBody,
            versionPattern: #"^\s*\{[^{}]*"build"\s*:\s*([0-9]+)[^{}]*\}\s*$"#,
            downloadURL: URL(string: "https://github.com/nekohasekai/open-screen-sharing/releases/tag/nightly"),
            changelogURL: URL(string: "https://github.com/nekohasekai/open-screen-sharing/releases/tag/nightly"),
            versionIsBuild: true,
            displayVersionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string:
                    "https://github.com/nekohasekai/open-screen-sharing/releases/download/nightly/OpenScreenSharing.pkg")!),
                kind: .pkg),
            channel: .nightly),
        ],
        changelogs: [
        // Nightly: the newest releases, prerelease and stable interleaved, by
        // publish date. The vendor's CI deletes the `nightly` release and
        // publishes a new one on every build, and GitHub's list still put it
        // below the older `v1.0.1` (2026-10-17, build 28), hence
        // `ordersByPublishedDate`.
        //
        // The `nightly` body lists only the commits since the PREVIOUS nightly
        // (`build.yml`: `git log nightly..` before the tag moves), and the earlier
        // nightly releases are deleted, so a copy several nightlies behind sees
        // the newest build's commits only; the stable entries carry each release's
        // commits since the stable before it. The nightly entry is labelled with
        // its tag (`nightly`), not a build number: the release states none.
        ChangelogRecipe(
            bundleID: "io.nekohasekai.screensharing",
            source: URL(string: "https://api.github.com/repos/nekohasekai/open-screen-sharing/releases?per_page=20")!,
            mode: .json,
            maxEntries: 20,
            channel: .nightly,
            includesPromotedStable: true,
            ordersByPublishedDate: true,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // Open Screen Sharing (nekohasekai/open-screen-sharing, Team P8XK3KHB48)
        // — installs as `/Applications/Screen Sharing.app`. The app's own
        // updater (`OpenScreenSharing/Update/UpdateChecker.swift`) reads
        // `/releases/latest` for its stable track, so this rule reads the same.
        //
        // The release asset is a component pkg with no scripts: `PackageInfo`
        // declares `./Screen Sharing.app` (this bundle id) under
        // `install-location="/Applications"`, so it takes the system-installer
        // route XQuartz uses. The release also carries an iOS `.ipa`, an
        // AltStore source and `metadata.json`; the asset pattern is the exact pkg
        // name.
        //
        // A copy set to the nightly track is served by the probe above. One whose
        // setting cannot be read (no Full Disk Access) is read as stable here, and
        // that never downgrades it — its marketing version is never behind the
        // latest stable release, which is a copy of an earlier nightly.
        GitHubReleaseRule(
            bundleID: "io.nekohasekai.screensharing",
            owner: "nekohasekai", repo: "open-screen-sharing",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenScreenSharing\.pkg$"#,
            installerKind: .pkg),
        ],
        channelProofs: [
        // The nightly pkg is served from the `nightly` release's own download
        // path, which names the track; the stable one is `/download/v<version>/`.
        ChannelProofKey("io.nekohasekai.screensharing", .nightly):
            .artifact(#"/open-screen-sharing/releases/download/nightly/OpenScreenSharing\.pkg$"#),
        ])
}
