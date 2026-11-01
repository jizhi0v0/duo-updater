import Foundation

enum net_activitywatch_ActivityWatch {
    static let bundleID = "net.activitywatch.ActivityWatch"

    /// A literal the Tauri edition's main executable carries (237 occurrences in
    /// the real 0.14.1 `aw-tauri`) and the classic build's `aw-qt` carries none
    /// of. It tells the two editions apart, nothing about a channel.
    static let tauriMarker = "tauri"

    /// The classic asset's name, in the form a one-click gate sees an offering.
    static let classicOffering =
        #"^GitHub:activitywatch-v[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$"#

    static let set = AppRecipeSet(
        family: "net-activitywatch-ActivityWatch",
        changelogs: [
        // ActivityWatch — one release body covers both macOS editions and the
        // installation/download/support boilerplate. The real change notes sit
        // under `# Changelog` → `## 📦 activitywatch` → `### ✨ Features (3)` /
        // `### 🐛 Fixes (7)`; the download tables and the contributor roll call
        // above it are skipped by heading. The stable tag pattern keeps the
        // `b<N>` prerelease tags (v0.14.0b8) out of the history.
        ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://api.github.com/repos/ActivityWatch/activitywatch/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: [
                "Installation", "Downloads", "Classic distribution",
                "Tauri distribution (experimental — native Wayland support on Linux)",
                "Support ActivityWatch", "Contributors", "Changelog",
            ],
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ],
        githubRules: [
        // ActivityWatch, classic (Python/Qt) distribution — the one the Homebrew
        // cask installs. Every release ships both editions under the same bundle
        // id, the same version and the same Team: the classic files are
        // `activitywatch-v<version>-macos-arm64.dmg`, the Tauri rewrite's are
        // `activitywatch-tauri-v<version>-…`. This rule installs the classic dmg;
        // the marked rule below answers for Tauri copies.
        //
        // Tags read `v0.14.1`; both version keys say 0.14.1. No updater ships in
        // the classic bundle (no `app-update.yml`, no Sparkle, no `checkForUpdates`
        // in its code), so nothing stages an update behind us. The Tauri build
        // embeds tauri-plugin-updater and reads GitHub's `/releases/latest`; it
        // is the experimental distribution the vendor's notes describe.
        //
        // Prereleases are tagged `v0.14.0b8` — the `b<N>` suffix no plain
        // version line has — so the anchored tag pattern never offers one, and a
        // copy installed from a prerelease reads behind stable and is offered the
        // graduation.
        GitHubReleaseRule(
            bundleID: bundleID,
            owner: "ActivityWatch", repo: "activitywatch",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^activitywatch-v[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$"#,
            installerKind: .dmg),

        // ActivityWatch, Tauri edition — same id, same version, same Team, and
        // the bundle even calls itself ActivityWatch.app; only the executable
        // differs (`aw-tauri` vs the classic `aw-qt`). Detection only: the
        // vendor labels this distribution experimental and the cask ships the
        // classic one, so a Tauri copy is shown its version but is not offered a
        // swap to the other edition's package.
        //
        // No `OneClickGate` guards the classic package, and that is measured:
        // the classic Info.plist says `CFBundleExecutable = MacOS/aw-qt` (a
        // PATH, not a file name), so every executable-marker gate fails closed on
        // it and the classic copy would lose its one-click — observed in the VM
        // as route `manual`. The marked rule above is the protection: a Tauri
        // copy's own executable is `aw-tauri`, a normal file name, so its marker
        // reads reliably and it never falls through to the classic rule.
        GitHubReleaseRule(
            bundleID: bundleID,
            owner: "ActivityWatch", repo: "activitywatch",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            variant: "tauri",
            installedExecutableMarker: tauriMarker),
        ])
}
