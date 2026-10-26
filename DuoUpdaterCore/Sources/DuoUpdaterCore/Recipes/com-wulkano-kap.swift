import Foundation

enum com_wulkano_kap {
    static let set = AppRecipeSet(
        family: "com-wulkano-kap",
        githubRules: [
        // Kap — open-source screen recorder (wulkano/kap, Electron). It updates
        // itself with electron-updater 4.6.1 (`provider: github`, which
        // `ElectronManifestSource` does not construct an address for): a check
        // at launch and every hour, the arm64 zip downloaded unasked into
        // `~/Library/Application Support/Caches/kap-updater/pending/` (the
        // pre-5 electron-updater path, measured; `SelfUpdaterStash` does not
        // read it), handed to Squirrel.Mac and
        // installed when Kap quits. The bundle carries only Electron's four
        // `Kap Helper*` child processes in `Contents/Frameworks`, which exit
        // with the app; no login item, LaunchAgent or daemon.
        //
        // Tags read `v3.6.0`; the bundle says 3.6.0 (build 3.6.0.1846). Each
        // release since v3.5.0 ships `Kap-<version>-arm64.dmg` beside an x64
        // dmg and two zips; this rule installs the arm64 dmg
        // (com.wulkano.kap, Team 2KEEHXF6R6, notarized; same id and Team back
        // to v0.1.0). v3.6.0 (2022-10-27) is the newest release.
        GitHubReleaseRule(
            bundleID: "com.wulkano.kap",
            owner: "wulkano", repo: "kap",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Kap-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
