import Foundation

enum org_torproject_torbrowser {
    static let set = AppRecipeSet(
        family: "org-torproject-torbrowser",
        probes: [
        // Tor Browser — the official Tor Project update-check JSON
        // (`aus1.torproject.org`, the same host the browser's own updater
        // consults). Single small object: `{"binary": "...", "version": "15.0.19",
        // ...}`, no other version-shaped numbers nearby, so a bare `"version"` key
        // match is safe here.
        //
        // Verified against the real install, not assumed: mounting the 15.0.19 dmg
        // gives CFBundleShortVersionString exactly `15.0.19` — same three-segment
        // scheme as the feed, no build/marketing mismatch to work around (unlike
        // Emacs, `Recipes/org-gnu-Emacs.swift`). org.torproject.torbrowser, Team MADPSAYN6T (The Tor
        // Project, Inc), notarized Developer ID, ticket stapled. `"binary"` is the
        // exact dmg URL for this version, so the install spec reads it straight
        // from the same response rather than templating one.
        VendorProbeRecipe(
            bundleID: "org.torproject.torbrowser",
            url: URL(string: "https://aus1.torproject.org/torbrowser/update_3/release/download-macos.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.torproject.org/download/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""binary"\s*:\s*"(https://[^"]+\.dmg)""#),
                kind: .dmg)),
        ])
}
