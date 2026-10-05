import Foundation

enum ai_memoh_desktop {
    static let set = AppRecipeSet(
        family: "ai-memoh-desktop",
        probes: [
        // History: docs/app-audits/ai-memoh-desktop.md#历史与实测
        // Memoh Desktop — Electron client for Memoh Cloud (electron-updater,
        // generic provider). No `SUFeedURL`, no cask; the open-source repo's
        // GitHub Releases stopped carrying desktop installers, so the vendor's own
        // `desktopresource.memoh.ai` is the only place the build is published. It
        // is also the host memoh.ai's download page reads (`latest-mac.yml`, then
        // the `-mac-arm64` entry).
        //
        // WHY A RECIPE AND NOT `ElectronManifestSource`: the bundle's own
        // `app-update.yml` says `channel: 1` — electron-builder took the `-1` of
        // the version as a semver prerelease and wrote it as the channel — so the
        // generic source asks for `1-mac.yml`, which 404s. The app itself never
        // reads that file: `apps/desktop/src/main/updates.ts` replaces the config
        // with `setFeedURL({ provider: 'generic', url })`, no channel, so its real
        // request is `latest-mac.yml`, the same one read here. Retire this recipe
        // only once the vendor stops stamping a channel into the bundle.
        //
        // VERSION: `YYYY.M.D-N` (a date and a per-day build counter), and the
        // bundle's CFBundleShortVersionString and CFBundleVersion both carry the
        // same string, suffix included. `VersionComparator` splits on `-`, so the
        // counter orders like a fourth component. Do NOT strip the suffix: the
        // installed side keeps it, and a stripped probe would read one build
        // behind forever. The pattern admits only a numeric counter, so a
        // `-beta.1` style suffix makes the probe miss (unknown) instead of
        // offering a non-stable build.
        //
        // No `stagingPercentage` in the manifest: every install reads the same
        // file, so the newest build on the track is the one this machine is
        // allocated.
        //
        // ONE-CLICK: the arm64 zip, resolved against the feed's own base; its
        // checksum is anchored on the arm64 `url:` line because the x64 entry sits
        // beside it and `path:` names the x64 zip. Signed `Developer ID
        // Application: Shenzhen Moerin Technology Co., Ltd. (P9R669C27U)`,
        // notarized, self-contained bundle (no launch items or helpers outside
        // the .app), so `kind: .zip` is right.
        VendorProbeRecipe(
            bundleID: "ai.memoh.desktop",
            url: URL(string: "https://desktopresource.memoh.ai/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*["']?([0-9]+(?:\.[0-9]+)+(?:-[0-9]+)?)["']?\s*$"#,
            downloadURL: URL(string: "https://memoh.ai/download"),
            publishedAtPattern: #"(?m)^releaseDate:\s*["']([^"'\s]+)["']\s*$"#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(?m)^\s*-\s*url:\s*["']?(Memoh-[0-9][^\s"'/]*-mac-arm64\.zip)["']?\s*$"#,
                    base: URL(string: "https://desktopresource.memoh.ai/")!),
                kind: .zip,
                checksumPattern: #"url:\s*["']?Memoh-[0-9][^\s"'/]*-mac-arm64\.zip["']?\s*\n\s*sha512:\s*["']?([A-Za-z0-9+/=]+)"#)),
        ],
        changelogs: [
        // Memoh Desktop — the open-source repo's GitHub releases. The desktop
        // build is the OSS tree with its version overridden at package time
        // (`MEMOH_DESKTOP_VERSION` → `-c.extraMetadata.version`, see
        // `apps/desktop/scripts/build-env.mjs`): only the top-level `package.json`
        // in `app.asar` is rewritten, and the bundled
        // `node_modules/@memohai/runtime/package.json` still says which OSS
        // version the build was cut from (`0.20.0` inside `2026.9.27-1`). So these
        // notes are this app's, numbered in the upstream namespace.
        //
        // WHY THE ENTRY KEEPS ITS `v`: `v0.20.0` and `2026.9.27-1` share no
        // numbering, and nothing in the feed says which OSS release a desktop
        // build carries, so no entry can be filed under the app's version. Kept as
        // the tag spells it, the entry is not version-shaped to `duo verify`'s
        // lag / lead checks (they require a leading digit), which would otherwise
        // read `0.20` vs `2026.9` as "a whole release behind" on every sweep.
        // `Changelog.carries` does strip the `v`, so the disk cache keeps this
        // page provisional and re-reads it — the same permissive direction it
        // takes for Raycast's and Toolbox's coarser numbering.
        //
        // Prereleases (`v0.9.0-beta.N` …) are dropped by the decoder's stable
        // filter, and the `$`-anchored pattern refuses them as well.
        ChangelogRecipe(
            bundleID: "ai.memoh.desktop",
            source: URL(string: "https://api.github.com/repos/felinics/Memoh/releases?per_page=20")!,
            mode: .json,
            maxEntries: 10,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^(v[0-9]+(?:\.[0-9]+){2})$"#),
        ])
}
