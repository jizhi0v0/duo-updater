import Foundation

enum MeowingCat_MacsyZones {
    static let set = AppRecipeSet(
        family: "MeowingCat-MacsyZones",
        githubRules: [
        // MacsyZones — a FancyZones-style window manager (rohanrhu/MacsyZones,
        // GPL-3.0); a menu-bar app (LSUIElement) with no nested helpers. Its
        // own updater (`Updater.swift`) reads this same /releases/latest at
        // every launch and, when the tag is newer, downloads the first asset,
        // swaps the bundle in place with a nohup script and relaunches; it
        // never re-checks while running, and parks nothing (the extracted app
        // lives in a temp dir the script removes). The Homebrew cask is
        // `auto_updates`, so this rule is what answers.
        //
        // Tags read `v3.1.1` / `v3.1`, the same as CFBundleShortVersionString
        // (CFBundleVersion is a constant 1); all 41 releases match, none is a
        // prerelease. The asset is `MacsyZones.zip` in every release but
        // v1.5 (`MacsyZones-1.5.zip`), hence the optional version.
        // One-click: universal zip, MeowingCat.MacsyZones, Team 59CP56H446 in
        // every release read (v1.1 through v3.1.1), notarized.
        GitHubReleaseRule(
            bundleID: "MeowingCat.MacsyZones",
            owner: "rohanrhu", repo: "MacsyZones",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MacsyZones(?:-[0-9.]+)?\.zip$"#,
            installerKind: .zip),
        ])
}
