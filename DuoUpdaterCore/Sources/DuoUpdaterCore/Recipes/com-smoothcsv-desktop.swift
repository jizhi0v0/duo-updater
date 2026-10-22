import Foundation

enum com_smoothcsv_desktop {
    static let set = AppRecipeSet(
        family: "com-smoothcsv-desktop",
        githubRules: [
        // SmoothCSV — a CSV editor built on Tauri 2 (`kohii/smoothcsv3`, a
        // releases-and-issues repo; the source is closed). Its own updater is
        // `tauri-plugin-updater` 2.10.1, reading `api.smoothcsv.com/api/updates`
        // (a 301 to this repo's `/releases/latest/download/latest.json`) and then
        // that `latest.json` directly — the same `/releases/latest` this rule
        // reads. The plugin keeps a download in memory (`DownloadedBytes`) and
        // swaps the bundle only when the app asks it to install; nothing is
        // parked on disk for `SelfUpdaterStash`. No login item, LaunchAgent or
        // helper app in the bundle; `Contents/MacOS/smoothcsv-cli` is the CLI
        // the app or Homebrew links into PATH, and it lives inside the bundle.
        //
        // Tags read `v3.26.0`; the bundle says 3.26.0 in both version fields.
        // `SmoothCSV_<version>_universal.dmg` is com.smoothcsv.desktop, Team
        // 46PHP2W2TP, notarized (3.0.0, 3.25.1 and 3.26.0 checked). The
        // `*_portable.zip` assets beside it are the Windows build, and
        // `SmoothCSV_universal.app.tar.gz` is the Tauri updater's archive.
        //
        // The `v3.0.0-beta.N` tags this pattern leaves out are not flagged
        // prerelease but are the pre-3.0 betas (2024-11 to 2025-06), older than
        // every stable tag; they are served by the beta rule below. The
        // `v0.1.0-alpha.N` tags are SmoothCSV 3's first alphas under another
        // bundle id (`com.smoothcsv`), unsigned — not this app's copies.
        GitHubReleaseRule(
            bundleID: "com.smoothcsv.desktop",
            owner: "kohii", repo: "smoothcsv3",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^SmoothCSV_[0-9]+(?:\.[0-9]+)+_universal\.dmg$"#,
            installerKind: .dmg),

        // A copy still on a 3.0.0 beta. Same bundle id and Team, but its
        // version (`3.0.0-beta.11` on the real artifact) makes
        // `ReleaseChannel.detect` call it beta, and the stable rule refuses it:
        // without this rule channel-verify reads "no source answered". The beta
        // train ended at 3.0.0 and the betas' own updater reads
        // `/releases/latest` too, so the release a beta copy moves to is the
        // newest stable one: same tags as the stable rule.
        //
        // Detection-only: a non-stable install needs a channel proof, and the
        // only thing that tells the two tracks apart is the installed version,
        // not anything in the release. Once the copy is on a stable version the
        // stable rule above serves it, one-click included.
        GitHubReleaseRule(
            bundleID: "com.smoothcsv.desktop",
            owner: "kohii", repo: "smoothcsv3",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            channel: .beta),
        ])
}
