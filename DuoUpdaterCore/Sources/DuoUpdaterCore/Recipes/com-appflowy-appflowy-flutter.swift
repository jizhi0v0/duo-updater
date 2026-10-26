import Foundation

enum com_appflowy_appflowy_flutter {
    static let set = AppRecipeSet(
        family: "com-appflowy-appflowy-flutter",
        githubRules: [
        // AppFlowy — open-source workspace / notes app (Flutter + Rust). From
        // 0.14.10 the bundle carries no Sparkle: the app asks its AppFlowy Cloud
        // server (`/api/desktop-update`) and, when there is a newer build, tells
        // the user to download the installer and open it. It never swaps its
        // own bundle. Copies up to 0.14.8 carry Sparkle 2.8.1 through
        // auto_updater, fed in code from this repo's
        // `releases/latest/download/appcast-macos-<arch>.xml`, with scheduled
        // checks off (user-initiated only); 0.14.11 publishes no appcast, so
        // that address answers 404. No helper or login item in the bundle.
        //
        // Tags read `0.14.11` (no `v`); the bundle says 0.14.11. Since 0.8.5
        // each release ships `-macos-arm64`, `-macos-universal` and
        // `-macos-x86_64` dmgs, all com.appflowy.appflowy.flutter, Team
        // VHB67HRSZG, notarized. 0.14.8 shipped only the arm64 dmg and no
        // universal one, so the rule installs the arm64 dmg: present in every
        // release since 0.8.5, and the file the vendor's own arm64 appcast
        // named. DuoUpdater itself runs on arm64 only.
        GitHubReleaseRule(
            bundleID: "com.appflowy.appflowy.flutter",
            owner: "AppFlowy-IO", repo: "AppFlowy",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^AppFlowy-[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
