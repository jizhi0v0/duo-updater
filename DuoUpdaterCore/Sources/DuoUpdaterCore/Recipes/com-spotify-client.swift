import Foundation

enum com_spotify_client {
    static let set = AppRecipeSet(
        family: "com-spotify-client",
        probes: [
        // Spotify — no cheap public version API (the cohort `upgrade.scdn.co`
        // endpoint is session-token-gated, not a configurable key). BUT the 1.8MB
        // "stub" web installer `download.scdn.co/SpotifyInstaller.zip` bundles an
        // `Install Spotify.app` whose CFBundleShortVersionString tracks the latest
        // CLIENT version in lockstep — verified 2026-06-16: stub `1.2.92.148` while
        // the installed app AND Homebrew's cask both lagged at `.147`, so the stub
        // is the FRESHEST surface (even ahead of brew's heavyweight `extract_plist`
        // of the 164MB dmg). The version sits behind two layers — a
        // deflate-compressed zip entry + a binary plist — so it needs the
        // `.zipEntryPlist` mode (text-regex / redirect modes can't reach it); the
        // pattern just validates the extracted string is a dotted version. Same
        // marketing scheme the app reports (4-component `1.2.x.y`), so not a build
        // recipe. One-click install pulls the full always-latest universal dmg
        // (`download.scdn.co/SpotifyARM64.dmg`, 164MB, fetched only at apply time) —
        // an in-place app swap gated by Spotify's Team 2FNC3A47ZF. changelogURL is
        // nil on purpose: spotify.com/release-notes tracks a DIFFERENT (mobile/web)
        // version scheme (`1.2.534.x`), so embedding it for a `1.2.92.x` desktop
        // build would show an unrelated page — better the honest "no notes" state.
        // No `changelogURL`, and not an oversight: Spotify publishes no release
        // notes for the desktop client anywhere. Checked 2026-08-22 — the only
        // things that exist are one-off community forum posts from a decade ago
        // (0.9.x, 1.0.9) and long-running threads asking for a changelog.
        VendorProbeRecipe(
            bundleID: "com.spotify.client",
            url: URL(string: "https://download.scdn.co/SpotifyInstaller.zip")!,
            mode: .zipEntryPlist(
                entry: "Install Spotify.app/Contents/Info.plist",
                key: "CFBundleShortVersionString"),
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            downloadURL: URL(string: "https://www.spotify.com/download/mac/"),
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string: "https://download.scdn.co/SpotifyARM64.dmg")!),
                kind: .dmg)),
        ])
}
