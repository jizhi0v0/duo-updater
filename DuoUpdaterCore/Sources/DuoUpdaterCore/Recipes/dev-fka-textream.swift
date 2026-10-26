import Foundation

enum dev_fka_textream {
    static let set = AppRecipeSet(
        family: "dev-fka-textream",
        githubRules: [
        // Textream — native SwiftUI teleprompter (f/textream). Its own
        // update check (`UpdateChecker.swift`, direct-download builds only)
        // reads this repo's /releases/latest at launch and from "Check for
        // Updates", and only offers to open the release page in the browser:
        // no download, no staging, no swap. No Sparkle, no helper, login item
        // or launch agent in the bundle. The Mac App Store edition shares
        // dev.fka.textream on its own version line; store copies never reach a
        // GitHub rule (`answersAppStoreCopies`).
        //
        // Tags read `v1.7.1`, equal to CFBundleShortVersionString (build 1).
        // Since v1.4.3 every release carries two builds of the same app, same
        // id, version, Team and LSMinimumSystemVersion 15.0: `Textream.dmg`
        // (Xcode 26 SDK) and `Textream-macos15.dmg` (Xcode 16.2 SDK); the one
        // Liquid Glass call (`glassEffect`, ContentView.swift) sits behind
        // `#available(macOS 26.0, *)` with a material fallback. The rule installs `Textream.dmg` for every copy,
        // as the Homebrew cask does on every macOS it supports. Copies up to
        // 1.6.3 are ad-hoc signed (no Team), so the Team gate refuses one-click
        // for them; Developer ID (Team RJA7656U34, notarized) since 1.6.4.
        GitHubReleaseRule(
            bundleID: "dev.fka.textream",
            owner: "f", repo: "textream",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Textream\.dmg$"#,
            installerKind: .dmg),
        ])
}
