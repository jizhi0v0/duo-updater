import Foundation

enum xyz_chatboxapp_app {
    static let set = AppRecipeSet(
        family: "xyz-chatboxapp-app",
        probes: [
        // MARK: - 2026-08-30 Chatbox

        // Chatbox — desktop client for OpenAI-compatible chat APIs (Electron,
        // electron-updater). No Sparkle: the real bundle (downloaded and mounted
        // 2026-08-30) carries no `SUFeedURL`, and the cask (`chatbox`) is
        // `auto_updates true`, which makes `HomebrewCaskSource` skip it — the
        // electron-builder feed is the only public "latest version" surface.
        // It is also EXACTLY the endpoint Homebrew's own `livecheck` block
        // resolves against (`strategy :electron_builder`), a third-party witness
        // that this is the vendor's intended version surface, not a guess.
        //
        // Feed shape: `version: 1.22.6` on the first line, then a `files:` list
        // pairing each artifact's relative `url:` with its base64 `sha512:`.
        // The arm64 dmg is resolved against `download.chatboxai.app/releases/`
        // and its sha512 verified from the feed — unlike Signal's yml, the hash
        // here IS the bytes the CDN serves: computed over the real downloaded
        // dmg 2026-08-30, byte-for-byte equal (151,499,252 bytes). The x64 dmg
        // and both zips are siblings we deliberately don't select; DuoUpdater
        // is arm64-only. Signed "Developer ID Application" (Team YJ5GSB3AMW,
        // notarized) — matches the mounted artifact, so the VendorInstaller
        // Team gate passes.
        //
        // `version` is the marketing string and equals the installed
        // CFBundleShortVersionString (1.22.6 == build 1.22.6); no versionIsBuild.
        //
        // Single channel, self-contained bundle (no daemons outside the .app) →
        // `kind: .dmg` is right.
        VendorProbeRecipe(
            bundleID: "xyz.chatboxapp.app",
            url: URL(string: "https://download.chatboxai.app/releases/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://chatboxai.app/en")!,
            // The yml is a manifest with no prose; the notes are on the vendor's
            // changelog page, same numbering. Parsed natively by the
            // `ChangelogRecipe` for `xyz.chatboxapp.app`.
            changelogURL: URL(string: "https://chatboxai.app/en/help-center/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Chatbox-[^\s]+-arm64\.dmg)"#,
                    base: URL(string: "https://download.chatboxai.app/releases/")!),
                kind: .dmg,
                checksumPattern: #"Chatbox-[^\n]+-arm64\.dmg\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),
        ],
        changelogs: [
        // Chatbox — the electron-builder feed we read for the version
        // (`latest-mac.yml`) is a manifest: filenames, sizes and hashes, no prose.
        // The vendor's own changelog page has the notes and uses the same
        // numbering as the feed (`v1.23.1` on the page, `version: 1.23.1` in the
        // yml, 2026-09-03).
        //
        // Each release renders as `<h2>v<ver> - <date></h2>` followed by TWO
        // lists: an `<ol>` of changes and a `<ul>` of per-platform download
        // links. The entry pattern binds the `<ol>` specifically — capturing up
        // to the next `<h2>` instead would put six download links ("MacOS(Apple
        // Silicon)", "Windows", …) into every release's notes. Validated against
        // the live page 2026-09-03: 30 entries, 1.23.1 → 4 items, 1.23.0 → 9,
        // and zero entries whose body contains a `download.chatboxai.app` link.
        ChangelogRecipe(
            bundleID: "xyz.chatboxapp.app",
            source: URL(string: "https://chatboxai.app/en/help-center/changelog")!,
            entryPattern:
                #"<h2>v(?<version>[0-9][0-9.]*) - (?<date>[0-9.]+)</h2>\s*<ol>(?<body>.*?)</ol>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 20),
        ])
}
