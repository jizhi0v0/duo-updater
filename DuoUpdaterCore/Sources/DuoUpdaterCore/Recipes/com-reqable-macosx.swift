import Foundation

enum com_reqable_macosx {
    static let set = AppRecipeSet(
        family: "com-reqable-macosx",
        changelogs: [
        // Reqable — the release body, sectioned BY PLATFORM: `### windows-
        // macos-linux-android-ios` for everything shared, then per-platform
        // sections for what only that platform got. The bullets are the
        // vendor's own `- ❗ [IMP] …` / `- 🐞 [FIX] …` lines, which
        // `GitHubMarkdownParser` extracts as-is (emoji and tag kept inline).
        //
        // `skipSections` drops the platform-only sections a Mac reader cannot
        // act on: `windows`, `linux`, `android-ios`, and the bare `android`/`ios`
        // if one appears. The shared `windows-macos-linux-android-ios` heading is
        // NOT in the list and must stay out of it — it carries the Mac notes too,
        // and the match is whole-heading, so a keyword wide enough to catch it
        // would empty most entries. A Windows-only release (3.3.8, whose entire
        // body is `### windows`) therefore parses to no items and is dropped,
        // which is right: no macOS build was published for it.
        ChangelogRecipe(
            bundleID: "com.reqable.macosx",
            source: URL(string: "https://api.github.com/repos/reqable/reqable-app/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: ["windows", "linux", "android-ios", "android", "ios"]),
        ],
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
