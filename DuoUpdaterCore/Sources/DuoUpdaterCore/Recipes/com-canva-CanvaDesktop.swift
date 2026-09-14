import Foundation

enum com_canva_CanvaDesktop {
    static let set = AppRecipeSet(
        family: "com-canva-CanvaDesktop",
        probes: [
        // History: docs/app-audits/com-canva-CanvaDesktop.md#历史与实测
        // Canva — an Electron shell (`NSPrincipalClass` AtomApplication,
        // Squirrel.framework) that self-updates through electron-updater. The feed
        // is not a guess: the bundle's own `Contents/Resources/app-update.yml` names
        // `provider: generic` at `https://desktop-release.canva.com`, and the
        // Homebrew cask's `livecheck` reads that host's `latest-mac.yml` with
        // `strategy :electron_builder`. The cask itself is `auto_updates true`, so
        // `HomebrewCaskSource` declines it by design — and it was a release behind
        // (1.123.1 against 1.124.0) when this was written. No `SUFeedURL`, no GitHub
        // repo, and the iTunes lookup for this bundle id returns 0 results, so the
        // probe is the only surface that answers at all.
        //
        // The two sides compare like-for-like: the feed's `version` and the shipped
        // bundle's `CFBundleShortVersionString` carry the same string (e.g. `1.124.0`).
        // Its `CFBundleVersion` is an unrelated number (e.g. `3597652.392500792`) that
        // appears nowhere
        // in the feed, which is why this is NOT `versionIsBuild`.
        //
        // Every pattern here ends at a run of digits and dots, and that is the
        // load-bearing detail. `beta-mac.yml` exists on the same host and answers
        // 200, but it is abandoned — `1.98.0-beta`, released 2024-11-12, against a
        // stable 1.124.0 from 2026-08-25 — so no beta recipe is registered and no
        // beta bundle id exists to carry one. The version pattern's trailing
        // `\s*$` is what makes that safe in the other direction too: publish a
        // `-beta` into the STABLE feed and the pattern matches NOTHING, so the app
        // degrades to "unknown" rather than capturing `1.98.0`, reporting a
        // prerelease as stable, and reading as a permanent downgrade against an
        // installed stable (e.g. 1.124.0). The artifact pattern is pinned the same way, so an
        // install can never resolve `Canva-1.98.0-beta-universal.dmg`.
        //
        // One-click: the dmg holds `Canva.app` and nothing else — no pkg, no
        // LaunchDaemon, no helper outside the bundle — so the bundle swap is the
        // whole update. (The cask's `zap` names a
        // `com.canva.availability-check-agent` LaunchAgent, the one thing that could
        // have argued for `.pkg`; it is in neither the dmg nor a machine that has
        // run Canva, so whatever writes it, the installer does not.) The dmg's app is
        // com.canva.CanvaDesktop under Team 5HD2ARTBFS, notarized (History has the
        // verification). Unlike Signal, whose feed hash predates its own stapling,
        // Canva's published base64 sha512 matches the served bytes exactly, so the
        // checksum gate is armed on top of the mandatory Team-ID one.
        //
        // The download host needs no `requestHeaders`, and that is measured rather
        // than assumed — it is the failure class that resolves fine and then dies at
        // download time, which is why AweSun carries a Referer and SourceForge a
        // deliberately non-browser UA. `desktop-release.canva.com` answers the
        // downloader's own `DuoUpdater/0.1` with 206 and honours a mid-file Range,
        // so both the plain fetch and the resume path work unadorned.
        //
        // No `changelogURL`, deliberately: Canva publishes no desktop release notes.
        // The changelogs on canva.dev belong to the Apps SDK and Connect APIs and
        // describe a different product, and www.canva.com answers a Cloudflare
        // interactive challenge, so nothing there could be confirmed to be a notes
        // page. `downloadURL` therefore points at the plain download page, which
        // does answer (200), rather than at the yml.
        VendorProbeRecipe(
            bundleID: "com.canva.CanvaDesktop",
            url: URL(string: "https://desktop-release.canva.com/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.canva.com/download/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Canva-[0-9][0-9.]*-universal\.dmg)"#,
                    base: URL(string: "https://desktop-release.canva.com/")!),
                kind: .dmg,
                checksumPattern:
                    #"Canva-[0-9][0-9.]*-universal\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),
        ])
}
