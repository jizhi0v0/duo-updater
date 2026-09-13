import Foundation

enum org_openlogi_openlogi {
    static let set = AppRecipeSet(
        family: "org-openlogi-openlogi",
        githubRules: [
        // OpenLogi — fast-moving native Logitech utility. The real 0.8.1 bundle
        // is `org.openlogi.openlogi` and carries neither Sparkle nor another
        // standard update feed in Info.plist; its Homebrew cask is
        // `auto_updates: true`, so Homebrew correctly defers to the app updater.
        // That updater's compiled-in stable manifest and release workflow both
        // point at AprilNEA/OpenLogi, where stable tags are exactly `vX.Y.Z` and
        // publishing is gated on both macOS DMGs existing. The anchored pattern
        // rejects prerelease suffixes rather than truncating one onto stable.
        //
        // One-click verified 2026-09-03 end to end: installed 0.8.2 in
        // `~/Applications`, `duo install` took it to 0.8.3. Mounted arm64 dmg:
        // org.openlogi.openlogi, short `0.8.3` == tag, Team 8U3ZJ258K9 (the same
        // Team 0.8.2 carries, so the swap gate passes), signed Developer ID and
        // accepted by `spctl` as Notarized Developer ID. Each release also ships
        // an `-macos-x86_64.dmg` plus Windows/Linux artifacts and a `.minisig`
        // beside every one of them, so the pattern pins the arm64 dmg and ends on
        // `.dmg$` — without the anchor `OpenLogi-v0.8.3-macos-arm64.dmg.minisig`
        // truncates onto a URL nobody published.
        //
        // ⚠️ Two facts worth not rediscovering. The app carries NO stapled
        // notarization ticket (0.8.2 and 0.8.3 both; it is how this vendor ships,
        // not a regression) — `SignatureVerifier` checks signature validity and
        // Team, never stapling, so the swap is unaffected, but Gatekeeper has to
        // resolve the ticket online at first launch. And `CFBundleVersion` is a
        // TIMESTAMP (`20260830.162827`), a different namespace from the tag —
        // harmless only because this source sets the remote build to nil, so the
        // comparison is marketing-only. Do not "improve" that by feeding the tag
        // in as a build.
        GitHubReleaseRule(
            bundleID: "org.openlogi.openlogi",
            owner: "AprilNEA", repo: "OpenLogi",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenLogi-v[0-9.]+-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
