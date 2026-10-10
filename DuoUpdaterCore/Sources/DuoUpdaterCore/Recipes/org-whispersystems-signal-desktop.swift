import Foundation

enum org_whispersystems_signal_desktop {
    static let set = AppRecipeSet(
        family: "org-whispersystems-signal-desktop",
        probes: [
        // History: docs/app-audits/org-whispersystems-signal-desktop.md#历史与实测
        // Signal — Stable + Beta. electron-builder feeds (one per channel). Stable
        // ships `org.whispersystems.signal-desktop`; Beta is a separate
        // "Signal Beta.app" (detected as `.beta` from its name). Signal self-updates
        // via electron-updater; one-click is best-effort on top of that. The same
        // yml we probe lists a **universal** `.dmg` (alongside per-arch zips) and we
        // resolve its filename against `updates.signal.org/desktop/`.
        //
        // Two per-channel gotchas, both found 2026-08-09:
        //
        // 1. The filenames are NOT the same shape across channels: stable is
        //    `signal-desktop-mac-universal-8.22.0.dmg`, beta carries an extra
        //    segment — `signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg`. Each
        //    pattern is pinned to its own channel's spelling rather than made
        //    optional, so neither feed's pattern can resolve the other channel's
        //    build. A rename here degrades to detection-only *silently* (a probe
        //    that resolves no install URL is an error nowhere), so the install-plan
        //    test is what has to catch it — that's why both ids are listed there.
        //
        // 2. NO checksumPattern, deliberately. The yml's `sha512`/`size` describe
        //    the dmg as electron-builder emitted it, *before* Signal's CI signs and
        //    staples it; the CDN serves the stapled file (larger on both channels;
        //    History has the byte count), so the feed hash can never match the
        //    bytes we download and a checksum gate would abort every install.
        //    (Typeless reads a structurally identical feed with delta 0 — this is
        //    Signal's pipeline, not electron-builder's, so don't "fix" it by copying
        //    Typeless.) Integrity still rests on VendorInstaller's mandatory gates,
        //    verified against both real dmgs: notarized Developer ID, Team
        //    U68MSDN6DR on both channels, and a signed bundle id that pins each
        //    channel to its own install.
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            url: URL(string: "https://updates.signal.org/desktop/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-mac-universal-[^\s]+\.dmg)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .dmg)),
        VendorProbeRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            url: URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://signal.org/download/"),
            changelogURL: URL(string: "https://github.com/signalapp/Signal-Desktop/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-beta-mac-universal-[^\s]+\.dmg)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .dmg),
            channel: .beta),
        ],
        changelogs: [
        // History: docs/app-audits/org-whispersystems-signal-desktop.md#历史与实测
        // Signal Stable + Beta — GitHub releases of signalapp/Signal-Desktop, the
        // page both probes link. One repo, one tag scheme: stable is `v8.30.0`,
        // beta is `v8.31.0-beta.1`, and GitHub's `prerelease` bit is set on exactly
        // the `-beta.N` tags. With the leading `v` stripped, each tag is the
        // version its channel's yml offers, so no `tagPattern` is needed.
        //
        // The notes are thin: one to three bullets of prose per release, often the
        // stock "Small tweaks, bug fixes, and performance enhancements" line, and
        // a beta's body is usually copied unchanged into the stable release that
        // follows it.
        //
        // The beta recipe reads prereleases only (`channel: .beta`) and does NOT
        // set `includesPromotedStable`: Signal Beta is a separate app whose feed
        // and artifact (`signal-desktop-beta-mac-universal-<ver>-beta.N.dmg`) are
        // always a `-beta.N` build, so a stable entry would describe a build this
        // install is never offered.
        ChangelogRecipe(
            bundleID: "org.whispersystems.signal-desktop",
            source: URL(string: "https://api.github.com/repos/signalapp/Signal-Desktop/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "org.whispersystems.signal-desktop-beta",
            source: URL(string: "https://api.github.com/repos/signalapp/Signal-Desktop/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            structuredFormat: .gitHubReleases),
        ],
        channelProofs: [
        ChannelProofKey("org.whispersystems.signal-desktop-beta", .beta): .artifact(#"signal-desktop-beta-mac-"#),
        ])
}
