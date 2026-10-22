import Foundation

enum glass_kagerou_phosphene {
    static let set = AppRecipeSet(
        family: "glass-kagerou-phosphene",
        githubRules: [
        // Phosphene — video wallpapers through a `com.apple.wallpaper`
        // ExtensionKit extension (Contents/Extensions/PhospheneExtension.appex,
        // glass.kagerou.phosphene.extension), menu bar app (LSUIElement).
        // From 1.4 it updates itself: Tiptoe over mxcl/AppUpdater reads this
        // repo's /releases, downloads the `Phosphene-<version>.dmg`, checks the
        // Team ID and swaps the bundle at an idle moment (auto-install on by
        // default). 1.0 has no updater; 1.1 to 1.3.0 only check
        // `releases/latest` and link to the releases page, they never download
        // or install. The check is daily before 1.11.2 and every four hours
        // from it. The prepared install lives in the running process, so a
        // quit drops it; while the app runs it can still install what it holds
        // after we swapped (docs/app-audits/glass-kagerou-phosphene.md,
        // 已停放整包).
        //
        // Tags read `v1.11.2` / `v1.8` / `v1.0`, and the short version is the
        // tag's (1.0, 1.1, 1.11.1, 1.11.2 read from the real packages). The
        // pattern reads all 19 tags. Bundle id and Team 52K336H235 are the
        // same from 1.0 to 1.11.2, all notarized; universal except 1.1
        // (arm64 only). `Phosphene.dmg` in v1.0 doesn't match the asset
        // pattern, which only matters if v1.0 were ever the latest again.
        GitHubReleaseRule(
            bundleID: "glass.kagerou.phosphene",
            owner: "kageroumado", repo: "phosphene",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Phosphene-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
