import Foundation

enum com_FluidApp_app {
    static let set = AppRecipeSet(
        family: "com-FluidApp-app",
        githubRules: [
        // FluidVoice — on-device dictation. Homebrew cask `fluidvoice` is
        // `auto_updates`, no `SUFeedURL`, so the row was unknown. Tags are
        // `vX.Y.Z`; the same repo also ships `vX.Y.Z-beta.N` macOS prereleases
        // and `windows-vX.Y.Z` Windows builds, so the pattern is anchored on
        // both ends rather than stripping a `v` off whatever comes first.
        //
        // ⚠️ Renamed altic-dev/Fluid-oss → altic-dev/FluidVoice. The old slug
        // 301s onto this one (`full_name` is FluidVoice). Pin the canonical
        // name: URLSession drops `Authorization` while following GitHub's 301,
        // and the fetch that actually returns the releases would come back
        // anonymous. See #135.
        //
        // One-click: each stable release ships `Fluid-oss-<ver>.dmg` beside a
        // zip of the same build. Mounted 1.6.9 dmg: com.FluidApp.app, short
        // `1.6.9` == tag (CFBundleVersion is a small counter `20`, not compared),
        // universal x86_64+arm64, Team V4J43B279J, notarized + stapled. The
        // filename keeps the old product token; the zip and the Windows
        // `FluidVoice_*_x64-setup.exe` share the release and must not match.
        GitHubReleaseRule(
            bundleID: "com.FluidApp.app",
            owner: "altic-dev", repo: "FluidVoice",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Fluid-oss-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
