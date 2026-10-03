import Foundation

enum com_dirijor_diri {
    static let set = AppRecipeSet(
        family: "com-dirijor-diri",
        changelogs: [
        // diri — release bodies from the releases API. The GitHub rule below
        // carries only the newest body, and upstream releases almost daily, so a
        // copy a few versions behind would see one version's notes. Bodies are
        // Markdown: `##` sections since 0.8.3, a `## diri <ver> — …` title over
        // `###` sections for 0.6.x–0.7.x, and plain bullets in between. No
        // section is boilerplate; the download notes are trailing paragraphs.
        ChangelogRecipe(
            bundleID: "com.dirijor.diri",
            source: URL(string: "https://api.github.com/repos/cristicretu/diri/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // diri — Rust app for running coding agents (cristicretu/diri). It does
        // not use Sparkle: no `SUFeedURL`, its own updater reads `appcast.json`,
        // a JSON asset on every release (`diri/UPDATING.md`), and the tap cask
        // declares `auto_updates true`, so `/releases/latest` is the only source
        // that answers. Every release is stable (none flagged prerelease); the
        // three early `diri-v0.4.x` tags carry no release and the anchored
        // pattern refuses them anyway. short == tag without the `v`.
        //
        // One-click: the zip is the stapled `.app` upstream's own updater
        // installs; com.dirijor.diri, Team A56RVNJ69X, notarized, the same Team
        // on 0.9.0 and 0.9.1. The bundle runs resident processes from
        // `Contents/Resources/bin` (the `dirijord-rs` Engine and a
        // `diri-holder` per session) that outlive the app. Upstream's own
        // updater replaces the bundle under them too: on launch the app hashes
        // the bundled Engine and, on a mismatch, has the old one persist state
        // and exit while the Holders keep their agents (`daemon_launch.rs`).
        // So the swap needs no restart beyond the app's own. It does need the
        // bundle path never to be missing — see the audit.
        GitHubReleaseRule(
            bundleID: "com.dirijor.diri",
            owner: "cristicretu", repo: "diri",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^diri-[0-9.]+-universal\.zip$"#,
            installerKind: .zip),
        ])
}
