import Foundation

enum ai_storyteller_photocraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-photocraft",
        githubRules: [
        // PhotoCraft — the first of storytold's seven "-craft" apps (Rust/egui
        // reimplementations of Adobe's suite). All seven share one release
        // pipeline, so this comment is the shared rationale; the other six
        // families point here.
        //
        // No SUFeedURL and no Sparkle framework: the apps have no in-app installer
        // (PrintCraft's Help ▸ Check for updates only reads this same
        // `/releases/latest` and opens the release page), so the GitHub release
        // is the source. v-tags; `packaging/macos/package.sh` stamps
        // CFBundleShortVersionString and CFBundleVersion with the numeric X.Y.Z
        // only, so short == tag on stable.
        //
        // The anchors are what keep release candidates out. The release workflow
        // means to flag `X.Y.Z-rc.N` as a prerelease, but PhotoCraft's
        // v0.1.1-rc.4 / rc.5 went out as ordinary releases, so `/releases/latest`
        // can land on an rc. The rc's Info.plist reads the bare X.Y.Z too, so an
        // unanchored pattern would offer `v0.2.1-rc.1` as "0.2.1" and then never
        // offer the real 0.2.1. The dmg pattern leaves no room for `-rc.N`, so an
        // rc as latest carries no matching asset and the source walks the list
        // back past it to the newest X.Y.Z; the anchored tag pattern is the
        // backstop (alone it turns an rc into no answer, not a wrong one).
        //
        // Assets: `<app>-<ver>-macos-universal.dmg` (universal, the only macOS
        // app build) beside `<app>-cli-<ver>-macos-universal.zip`, which the
        // pattern excludes. GitHub publishes a sha256 digest for every asset.
        // One-click: ai.storyteller.photocraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.photocraft",
            owner: "storytold", repo: "photocraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^photocraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
