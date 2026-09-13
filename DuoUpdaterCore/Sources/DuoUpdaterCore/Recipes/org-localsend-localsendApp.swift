import Foundation

enum org_localsend_localsendApp {
    static let set = AppRecipeSet(
        family: "org-localsend-localsendApp",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // LocalSend — the reason `installAssetPattern` doubles as the macOS-release
        // gate. Upstream builds Windows/Linux/Android on CI but the dmg by hand
        // (`support/scripts/compile_mac_dmg.sh`, one maintainer, Developer ID +
        // notarization), and version numbers are shared across all five platforms
        // out of a single `pubspec.yaml`. So a mobile-only hotfix advances the tag
        // without producing a macOS build: v1.18.1 (2026-08-12) ships four `.apk`
        // files and says so in its own release notes — "Android+iOS only hotfix".
        // Reading the tag alone reported a 1.18.0 → 1.18.1 update that nobody can
        // ever install. With the pattern set, resolution walks back to v1.18.0,
        // which is genuinely the newest macOS release (Homebrew's cask and the
        // vendor's own download page both agree).
        //
        // The CLI tarballs (`LocalSend-CLI-1.18.0-macos-arm-64.tar.gz`) and the
        // Windows zip share the prefix, so the pattern anchors both ends.
        // Mounted dmg: org.localsend.localsendApp 1.18.0 (60), Team 3W7H4PYMCV,
        // hardened runtime, `spctl -a -t install` accepted.
        GitHubReleaseRule(
            bundleID: "org.localsend.localsendApp",
            owner: "localsend", repo: "localsend",
            installAssetPattern: #"^LocalSend-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
