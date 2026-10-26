import Foundation

enum com_reqable_macosx {
    static let set = AppRecipeSet(
        family: "com-reqable-macosx",
        githubRules: [
        // Reqable — HTTP debugging proxy (Flutter, closed source; reqable/reqable-app
        // is its issue tracker and release host). It updates itself with Sparkle
        // 2.8.0 through the auto_updater plugin, the feed set at runtime (no
        // SUFeedURL): `/version/smart-appcast?version=<build>&platform&arch&ext&locale`,
        // whose one item's enclosure is this repo's own release asset. The generic
        // Sparkle source can't read a feed that isn't in the bundle, so this rule
        // reads the same releases directly.
        //
        // Nothing resident ships in the bundle: `Resources/proxy-helper` is a
        // one-shot setuid tool the app copies to /Library/Application Support/Reqable/
        // (byte-identical from 2.21.2 to 3.3.5), and `Helpers/mcp-server` is spawned
        // by MCP clients. A bundle swap leaves both exactly as Sparkle's own swap does.
        //
        // Tags read `3.3.5`; the bundle says 3.3.5 (build 227). Each release carries
        // `reqable-app-macos-arm64.dmg` and `reqable-app-macos-x86_64.dmg`
        // (com.reqable.macosx, Team DXY5A5J7C4, notarized; same id and Team back to
        // 1.1.5). DuoUpdater is arm64-only (`App/project.yml`), so the pattern
        // anchors `-arm64`. A few releases ship no macOS asset (3.2.20–3.2.22) and
        // are walked past. The `test` tag (a 3.2.23 build) is not a version.
        GitHubReleaseRule(
            bundleID: "com.reqable.macosx",
            owner: "reqable", repo: "reqable-app",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^reqable-app-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
