import Foundation

enum com_ameba_SwiftBar {
    static let set = AppRecipeSet(
        family: "com-ameba-SwiftBar",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // SwiftBar — the newest release is often a beta prerelease (e.g. `v2.1.2-beta-3`),
        // so `/releases/latest` is what pins the rule to stable. The asset carries
        // the build number (e.g. `SwiftBar.v2.1.1.b597.zip`) that the tag doesn't, so the
        // pattern matches the version-plus-build shape rather than the tag.
        // One-click: com.ameba.SwiftBar, Team X93LWC49WV, notarized.
        GitHubReleaseRule(
            bundleID: "com.ameba.SwiftBar",
            owner: "swiftbar", repo: "SwiftBar",
            installAssetPattern: #"^SwiftBar\.v[0-9.]+\.b[0-9]+\.zip$"#,
            installerKind: .zip),
        ])
}
