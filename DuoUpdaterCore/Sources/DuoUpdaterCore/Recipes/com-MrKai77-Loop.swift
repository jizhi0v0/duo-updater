import Foundation

enum com_MrKai77_Loop {
    static let set = AppRecipeSet(
        family: "com-MrKai77-Loop",
        githubRules: [
        // Loop (MrKai77/Loop, Team 5F967GYF84, notarized) — window manager, no
        // SUFeedURL since 1.1.0. Its own updater (`Loop/Updater/`) reads
        // `/releases/latest` for the stable channel, takes the tag as the
        // version and installs the release's `.zip` asset.
        //
        // Stable track only. Every release attaches one universal `Loop.zip`.
        // Stable tags are bare `MAJOR.MINOR.PATCH` (1.0.0 … 1.4.2); the
        // `1.0.0-beta.N` tags are not flagged prerelease, so the pattern is
        // anchored to keep them out. The Development channel is one rolling
        // prerelease under the constant tag `prerelease`, versioned only in
        // the release name; it is not wired, see the audit.
        GitHubReleaseRule(
            bundleID: "com.MrKai77.Loop",
            owner: "MrKai77", repo: "Loop",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Loop\.zip$"#,
            installerKind: .zip),
        ])
}
