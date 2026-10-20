import Foundation

enum io_lapce {
    static let set = AppRecipeSet(
        family: "io-lapce",
        githubRules: [
        // Lapce (lapce/lapce) — a code editor written in Rust. No SUFeedURL; it
        // carries its own updater (`lapce-app/src/update.rs`): an hourly check of
        // `releases/latest` that only shows "Restart to update", and on that
        // click downloads `Lapce-macos.dmg`, swaps `Lapce.app` and relaunches.
        // Nothing is downloaded before the click, so it does not race us. No
        // helpers in the bundle.
        //
        // Tags read `vX.Y.Z`; the release commit stamps the same number into the
        // checked-in Info.plist template (`CFBundleShortVersionString`, build
        // always `1`). `Lapce-macos.dmg` (universal; the name carries no version)
        // is io.lapce, Team CYSGAZFR8D, notarized, at v0.4.6 and v0.4.5 alike.
        //
        // The `nightly` prerelease is re-created every day under the same tag
        // and asset name, the same id, Team and Info.plist (it says the last
        // release's version). `/releases/latest` never returns it, and a
        // nightly copy is told apart by its executable (`LapceBuild`), so this
        // stable rule steps aside for it rather than installing stable over it.
        GitHubReleaseRule(
            bundleID: "io.lapce",
            owner: "lapce", repo: "lapce",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Lapce-macos\.dmg$"#,
            installerKind: .dmg),
        ])
}
