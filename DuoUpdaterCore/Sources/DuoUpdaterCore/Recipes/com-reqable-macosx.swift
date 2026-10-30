import Foundation

enum com_reqable_macosx {
    static let set = AppRecipeSet(
        family: "com-reqable-macosx",
        githubRules: [
        // Reqable — Flutter HTTP debugging proxy (reqable/reqable-app). It does
        // ship Sparkle: `Sparkle.framework` and the `auto_updater` Flutter
        // plugin are both in the bundle, and Info.plist carries `SUPublicEDKey`.
        // But it carries no `SUFeedURL` — the feed address is handed to Sparkle
        // at runtime, out of a string table — so no Sparkle source can read it,
        // and there is no `app-update.yml` either. The vendor's releases are
        // what it publishes and what the Homebrew cask installs from, so this
        // rule is the route.
        //
        // Tags are bare `3.3.9`; the release *name* is what adds the `v`. The
        // bundle says 3.3.7 and its CFBundleVersion is `229`, a build number
        // rather than the marketing version, so only the tag is compared.
        //
        // Each macOS release carries `reqable-app-macos-arm64.dmg` beside the
        // android/linux/windows packages — but a Windows-only release does
        // happen (3.3.8 ships no macOS asset at all). `GitHubReleasesSource`
        // walks past up to five such releases before it gives up, which is what
        // keeps that from reading as "unknown". One-click installs the dmg:
        // com.reqable.macosx, Team DXY5A5J7C4, notarized.
        GitHubReleaseRule(
            bundleID: "com.reqable.macosx",
            owner: "reqable", repo: "reqable-app",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^reqable-app-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
