import Foundation

enum com_egoist_pulse {
    static let set = AppRecipeSet(
        family: "com-egoist-pulse",
        probes: [
        // History: docs/app-audits/com-egoist-pulse.md#历史与实测
        // Pulse (egoist, Team GJE9R5VE87) — an activity monitor built with
        // egoist's Go toolkit MyGo, the same toolkit and the same update manifest
        // as Moshi Go (`app-getmoshi-desktop.swift`). No Sparkle, no
        // electron-builder config. The address is the one the app's own updater
        // reads, `releases/latest/download/update-darwin-arm64.json` on
        // `egoist/pulse-feedback` (the repo holds issues and release assets, no
        // source). Its `url`s are absolute and name the versioned release
        // (`releases/download/v<version>/…`), not the moving `latest` alias.
        //
        // This replaces a GitHubReleaseRule on the same repo's dmg: that source
        // sits ahead of this one in `SourceStack`, so the two cannot coexist, and
        // only this route takes MyGo's deltas and checks the vendor's signature.
        //
        // The body is one release followed by `deltas[]` and `previous[]`, and
        // `previous[]` repeats `version`/`url` for older builds. Every pattern is
        // tempered so it cannot cross `"deltas"` or `"previous"`: version, date
        // and download all come from the top-level release.
        //
        // No rollout field: every install reads the same file, so the newest
        // build on the track is the one this machine is allocated. Apple silicon
        // only: the build is a single arm64 slice and no darwin-amd64 manifest is
        // published.
        //
        // ONE-CLICK: the top-level `.tar.gz` holds `Pulse.app` alone (no helpers,
        // no login items), signed by Team GJE9R5VE87 and notarized. The body
        // publishes no digest, so there is no `checksumPattern`; its `signature`
        // (below) is checked on top of the Team-ID gate.
        //
        // DELTAS: `deltas[]` are MyGo's `mygo delta 1` patches, read out of this
        // body by `MyGoManifest` and applied by `MyGoDelta`. As with Moshi Go,
        // the `.tar.gz` build carries a stray `Contents/CodeResources` that the
        // website's `.dmg` build lacks, and a patch rebuilds that file from the
        // installed one. So a copy installed from the dmg fails the patch and the
        // install retries with the full archive; a copy that came from the
        // `.tar.gz` (this one-click, or the app's own updater) takes the patch.
        //
        // `myGoPublicKey` is Pulse's MyGo update key, the string MyGo links into
        // the binary. Every `signature` in the feed, deltas and archives alike,
        // verifies against it over the file's SHA-256. A patch whose signature
        // does not is refused and the install takes the full archive; an archive
        // whose signature does not ends the install. If the vendor rotates the
        // key, one-click stops until this value is updated (see
        // `VendorInstallSpec.myGoPublicKey`).
        VendorProbeRecipe(
            bundleID: "com.egoist.pulse",
            url: URL(string: "https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json")!,
            mode: .responseBody,
            versionPattern:
                #"\A(?:(?!"deltas"|"previous")[\s\S])*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://github.com/egoist/pulse-feedback/releases/latest"),
            publishedAtPattern:
                #"\A(?:(?!"deltas"|"previous")[\s\S])*?"date"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"\A(?:(?!"deltas"|"previous")[\s\S])*?"url"\s*:\s*"(https://[^"]+\.tar\.gz)""#),
                kind: .tarGz,
                myGoPublicKey: "WzJsOGNIuf6mcEqo5ff8jub+NoQQOEk4JXreLPYjgyQ=")),
        ],
        changelogs: [
        // Pulse — the release list of `egoist/pulse-feedback`. The manifest above
        // carries the notes of the newest release only; each release body is the
        // same text, a plain `- ` list, for every version.
        ChangelogRecipe(
            bundleID: "com.egoist.pulse",
            source: URL(
                string: "https://api.github.com/repos/egoist/pulse-feedback/releases?per_page=40")!,
            mode: .json,
            maxEntries: 40,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ])
}
