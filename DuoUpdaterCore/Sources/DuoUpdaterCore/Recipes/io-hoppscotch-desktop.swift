import Foundation

enum io_hoppscotch_desktop {
    static let set = AppRecipeSet(
        family: "io-hoppscotch-desktop",
        githubRules: [
        // Hoppscotch (hoppscotch/releases, Team XBK86CMQGZ, notarized) — a Tauri
        // v2 API client. No SUFeedURL; its own updater (tauri-plugin-updater
        // 2.3.1) reads releases.hoppscotch.com, downloads into memory and swaps
        // the bundle when the user accepts, so nothing is parked on disk.
        //
        // Every release ships two editions under the same id and Info.plist:
        // Cloud (`Hoppscotch_mac_<arch>.dmg`) and SelfHost
        // (`Hoppscotch_SelfHost_mac_<arch>.dmg`); only the executable differs
        // (the updater endpoint it was built with). Two rules, one per edition:
        // the SelfHost rule answers for copies whose executable names the
        // SelfHost feed, this one for every other copy. The gates below keep
        // each edition's package to that edition's copies.
        //
        // Tags read `v26.9.0-0`; the bundle says 26.9.0 from v25.2.0-0 on. The
        // first generation (v23.8.3-1 … v25.1.1-2) kept the suffix in the bundle
        // (`25.1.1-2`, `25.1.1-0`), so the pattern reads every tag's base
        // version and the suffix is dropped. A release that ships SelfHost
        // assets only (v26.6.1-0) has nothing to install for Cloud, and this
        // rule passes over it.
        // History: docs/app-audits/io-hoppscotch-desktop.md#历史与实测
        GitHubReleaseRule(
            bundleID: "io.hoppscotch.desktop",
            owner: "hoppscotch", repo: "releases",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)-[0-9]+$"#,
            installAssetPattern: #"^Hoppscotch_mac_(?:aarch64|x64)\.dmg$"#,
            installerKind: .dmg),
        // SelfHost: same tags, its own dmg. Chosen only for a copy whose
        // executable contains the SelfHost feed name; a copy with neither
        // literal (x64 builds, unreadable executables) stays on the rule above.
        GitHubReleaseRule(
            bundleID: "io.hoppscotch.desktop",
            owner: "hoppscotch", repo: "releases",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)-[0-9]+$"#,
            installAssetPattern: #"^Hoppscotch_SelfHost_mac_(?:aarch64|x64)\.dmg$"#,
            installerKind: .dmg,
            variant: "selfhost",
            installedExecutableMarker: "hoppscotch-selfhost-desktop.json"),
        ],
        oneClickGates: [
            // First generation (`Hoppscotch` executable, central-desktop.json
            // updater, still pinned at v25.1.1-2): its bundle version keeps the
            // tag's `-N`. The vendor never moved those copies to the second
            // generation; replacing one is a manual step.
            OneClickGate(
                bundleID: "io.hoppscotch.desktop",
                requirement: .installedVersion(pattern: #"^[0-9]+(?:\.[0-9]+)+$"#),
                reason: "this is the first-generation Hoppscotch app; install the current one from hoppscotch.com/download"),
            // Cloud's arm64 executable names its updater feed
            // `…/hoppscotch-cloud-desktop.json`; SelfHost's names
            // `…/hoppscotch-selfhost-desktop.json`. The x64 builds hold neither
            // literal whole (only fragments such as `ch-cloud`), so an x64 copy
            // is withheld too. Each edition's package goes only to a copy with
            // that edition's literal; any other offer for this id (the
            // `hoppscotch-selfhost` cask among them) is withheld.
            OneClickGate(
                bundleID: "io.hoppscotch.desktop",
                requirement: .executableContains(marker: "hoppscotch-cloud-desktop.json"),
                reason: "this is not a proven Cloud edition copy (Self-Host, or an Intel build) and the update is the Cloud edition; update it from its own updater",
                offering: #"^(?:GitHub:Hoppscotch_mac_(?:aarch64|x64)\.dmg|Homebrew:hoppscotch)$"#),
            OneClickGate(
                bundleID: "io.hoppscotch.desktop",
                requirement: .executableContains(marker: "hoppscotch-selfhost-desktop.json"),
                reason: "this is not a proven Self-Host edition copy (Cloud, or an Intel build) and the update is the Self-Host edition; update it from its own updater",
                offering: #"^GitHub:Hoppscotch_SelfHost_mac_(?:aarch64|x64)\.dmg$"#),
        ])
}
