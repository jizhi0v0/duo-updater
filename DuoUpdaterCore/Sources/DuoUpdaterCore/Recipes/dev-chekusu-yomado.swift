import Foundation

enum dev_chekusu_yomado {
    static let set = AppRecipeSet(
        family: "dev-chekusu-yomado",
        githubRules: [
        // History: docs/app-audits/dev-chekusu-yomado.md#历史与实测
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
        // One zip per release, arm64 only, beside the SHA256SUMS text and (up to
        // 0.3.5) `Yomado-source-v*.zip`. The app zip is `Yomado-vX.Y.Z.zip` up to
        // 0.3.5 and plain `Yomado.zip` from 0.3.6, so the pattern takes both and
        // still not the source zip. 0.3.1 and 0.3.2 are ad-hoc signed, so the Team
        // gate refuses their one-click (no Team on the installed copy); see the audit.
        //
        // From 0.3.6 the app embeds Sparkle with its own `SUFeedURL`, so a copy that
        // new is answered by its feed; this rule is what copies up to 0.3.5, which
        // carry no feed, see newer releases through.
        GitHubReleaseRule(
            bundleID: "dev.chekusu.yomado",
            owner: "chekusu", repo: "yomado",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Yomado(?:-v[0-9]+\.[0-9]+\.[0-9]+)?\.zip$"#,
            installerKind: .zip),
        ])
}
