import Foundation

enum dev_chekusu_yomado {
    static let set = AppRecipeSet(
        family: "dev-chekusu-yomado",
        githubRules: [
        // yomado (chekusu/yomado, Team FKSR2JD63B from v0.3.3) — a menu-bar app
        // that runs virtual displays for visual agents. No SUFeedURL; its own
        // `app/UpdateChecker.m` only reads the releases list and links to the
        // release page, never downloads or installs.
        //
        // Every release is flagged prerelease ("yomado is currently
        // experimental", the checker's own comment), so `/releases/latest`
        // answers 404 and the rule must read the list. That is one track, not a
        // beta beside a stable: the app has no channel setting and its checker
        // takes the highest SemVer tag of all releases. Tags are `vX.Y.Z` and
        // `Info.plist` carries the same `X.Y.Z` (checked on 0.3.1–0.3.3); the
        // anchored pattern leaves any future `-suffix` tag unread.
        //
        // One zip per release, arm64 only, beside `Yomado-source-v*.zip` and the
        // SHA256SUMS text. 0.3.1 and 0.3.2 are ad-hoc signed, so the Team gate
        // refuses their one-click (no Team on the installed copy); see the audit.
        GitHubReleaseRule(
            bundleID: "dev.chekusu.yomado",
            owner: "chekusu", repo: "yomado",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Yomado-v[0-9]+\.[0-9]+\.[0-9]+\.zip$"#,
            installerKind: .zip),
        ])
}
