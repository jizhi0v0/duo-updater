import Foundation

enum now_typeless_desktop {
    static let set = AppRecipeSet(
        family: "now-typeless-desktop",
        probes: [
        // Typeless (now.typeless.desktop) — AI voice dictation, Electron app that
        // self-updates via electron-updater (Squirrel.Mac). No Sparkle feed in
        // Info.plist; the Homebrew cask is `auto_updates true` so brew never answers
        // — the only public "latest version" surface is the electron-builder feed.
        // Single stable channel (no beta/canary anywhere). The vendor splits by arch:
        // `arm64-mac.yml` for Apple Silicon (what we probe), `latest-mac.yml` for x64.
        // The feed's `version` is the marketing version (1.8.0) and matches the
        // installed app's CFBundleShortVersionString exactly (build is 1.8.0.109 — we
        // do NOT compare against that), so no versionIsBuild. One-click: the same yml
        // lists `Typeless-<ver>-arm64.dmg`; we resolve its filename against
        // typeless-static.com/desktop-release/ and verify the dmg's base64 sha512 from
        // the line right after its `url:` — on top of VendorInstaller's mandatory
        // same-Team gate (installed Team 947QKAND4W). No public changelog page exists.
        VendorProbeRecipe(
            bundleID: "now.typeless.desktop",
            url: URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://typeless.com/"),
            changelogURL: URL(string: "https://www.typeless.com/help/release-notes/macos"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Typeless-[^\s]+-arm64\.dmg)"#,
                    base: URL(string: "https://typeless-static.com/desktop-release/")!),
                kind: .dmg,
                checksumPattern: #"Typeless-[^\n]+-arm64\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),
        ],
        changelogs: [
        // Typeless — the release-notes page ships every version's notes (with a
        // hero image per release) base64+gzip'd inside the Next.js `__NEXT_DATA__`.
        // No regex can read that, so the structured decoder inflates it and emits
        // rich entries (image + prose blocks). Single channel. `maxEntries` caps the
        // long history (20 versions back to 0.1.0) at the most recent handful. The
        // page lists an upcoming version a few days ahead of its date; that's fine —
        // the changelog is informational and the vendor probe still gates "update
        // available" on the GA electron-builder feed.
        ChangelogRecipe(
            bundleID: "now.typeless.desktop",
            source: URL(string: "https://www.typeless.com/help/release-notes/macos")!,
            maxEntries: 12,
            structuredFormat: .typelessReleaseNotes),
        ])
}
