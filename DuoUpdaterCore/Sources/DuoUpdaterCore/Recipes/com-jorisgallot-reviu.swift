import Foundation

enum com_jorisgallot_reviu {
    static let set = AppRecipeSet(
        family: "com-jorisgallot-reviu",
        githubRules: [
        // Reviu — Rust/GPUI review app for agent-written code. No SUFeedURL; its
        // own updater POSTs api.reviu.dev/desktop/update/check, which answers
        // the GitHub release's version and the same dmg sha256 (no device id
        // in the request, so no staged rollout to be ahead of). v-tags,
        // single stable track (the Dev profile is debug builds only, not
        // shipped). `-macos-aarch64` and `-macos-x86_64` dmgs ship together; pin
        // aarch64. short == tag; CFBundleVersion is a build timestamp. Team
        // V3N3ZQ3643, notarized.
        GitHubReleaseRule(
            bundleID: "com.jorisgallot.reviu",
            owner: "reviu-dev", repo: "reviu",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Reviu-[0-9.]+-macos-aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
