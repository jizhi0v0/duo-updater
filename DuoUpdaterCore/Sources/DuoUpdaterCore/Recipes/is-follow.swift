import Foundation

enum is_follow {
    static let set = AppRecipeSet(
        family: "is-follow",
        githubRules: [
        // Folo (formerly Follow) — Electron RSS reader from the RSSNext/Folo
        // monorepo. Its own updater is electron-updater with a custom provider
        // that asks `ota.folo.is/manifest`; that manifest points at the same
        // GitHub release assets this rule reads. It downloads on its own and
        // Squirrel.Mac's ShipIt applies the download on quit. A renderer-only hot
        // update lands in userData and never changes the bundle version.
        //
        // The repo also tags the mobile app (`mobile/v0.6.1`, no macOS assets);
        // the anchored pattern leaves those out. Desktop tags were bare `v0.x.y`
        // until 0.9.0, then `desktop/v1.16.0`; both are this app. `-beta.N` /
        // `-alpha.N` tags of the Follow era are not flagged prerelease, and the
        // anchor keeps them out too.
        //
        // `Folo-<v>-macos-arm64.dmg` is is.follow, Team 492J8Q67PF, notarized,
        // from 0.3.4-beta.0 on; copies at 0.3.3-beta.0 and older are Team
        // NCLY2BLCL2 and the install gate refuses them. Audit:
        // docs/app-audits/is-follow.md.
        GitHubReleaseRule(
            bundleID: "is.follow",
            owner: "RSSNext", repo: "Folo",
            versionPattern: #"^(?:desktop/)?v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Folo-[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
