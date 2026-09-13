import Foundation

enum org_qbittorrent_qBittorrent {
    static let set = AppRecipeSet(
        family: "org-qbittorrent-qBittorrent",
        githubRules: [
        // qBittorrent is NOT a VendorProbe recipe — it moved to a GitHub release rule (see
        // `GitHubReleasesSource`). Upstream publishes the same macOS dmg on both
        // SourceForge and GitHub Releases, and GitHub is the better read: no WAF
        // to work around (`VendorProbeRegistry.sourceForgeMacRecipe` sends a UA override),
        // and the tag is the release itself rather than a "best release" guess.
        // It stays detection-only either way — that is a property of upstream's
        // signature, not of the endpoint.

        // qBittorrent — DETECTION ONLY, and this is upstream's own signature, not
        // a property of where we read from: the macOS dmg on GitHub is the SAME
        // artifact SourceForge serves, signed `Authority=qbittorrent macos` with
        // `TeamIdentifier=not set` (a self-made certificate, not a Developer ID),
        // and `spctl -a -t install` rejects it. Verified 2026-08-16 by downloading
        // `qbittorrent-5.2.3.dmg` (48,317,381 B) straight from this repo's release
        // and mounting it — org.qbittorrent.qBittorrent, 5.2.3, universal, and
        // rejected. No `installAssetPattern`, so the row shows the version and
        // opens qbittorrent.org.
        //
        // Read here rather than from SourceForge (where this app lived until
        // 2026-08-16) because the tag IS the release — SourceForge's
        // `best_release.json` answers with a Windows `.exe` at top level and hides
        // the dmg under `platform_releases.mac`, and its edge WAF needs the UA
        // override the remaining SourceForge recipes carry.
        //
        // Tag shape is `release-5.2.3`, so the pattern is anchored rather than
        // left to the default `v?(…)`: the repo also carries old `v3.3.x` tags,
        // and an unanchored match on a stray digit is exactly how a version
        // silently becomes wrong.
        GitHubReleaseRule(
            bundleID: "org.qbittorrent.qBittorrent",
            owner: "qbittorrent", repo: "qBittorrent",
            versionPattern: #"^release-([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
