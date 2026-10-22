import Foundation

enum com_logseq_logseq {
    static let set = AppRecipeSet(
        family: "com-logseq-logseq",
        githubRules: [
        // Logseq 2.x — the database-graph edition (logseq/logseq). The file-graph
        // edition moved to logseq/og as "Logseq OG", its own app; the 0.10.x
        // builds this repo shipped before 2.0 are `com.electron.logseq`, Team
        // 3K44EUN829, so this rule never sees them (and must not: a different
        // product, see the audit).
        //
        // Tags are bare versions (`2.0.2`) equal to CFBundleShortVersionString.
        // The anchored pattern leaves out the repo's other products: `mobile-0.1`
        // (an Android APK), `0.0.1-100` (a backend jar), `v0.0.1` (the publishing
        // tarball), and the rolling `nightly` prerelease.
        //
        // electron-updater (github provider, `latest-arm64` channel) checks and
        // downloads on launch but never installs on quit; it reads the same
        // /releases/latest. A nightly build carries the same plist as stable, and
        // its own updater moves it to the next stable too, so it is not gated.
        //
        // One-click: the arm64 dmg (no universal build), com.logseq.logseq,
        // Team K378MFWK59, notarized; 2.0.1 is the same Team.
        // History: docs/app-audits/com-logseq-logseq.md#历史与实测
        GitHubReleaseRule(
            bundleID: "com.logseq.logseq",
            owner: "logseq", repo: "logseq",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Logseq-darwin-arm64-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
