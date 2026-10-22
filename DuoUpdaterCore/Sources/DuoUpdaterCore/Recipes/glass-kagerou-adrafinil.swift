import Foundation

enum glass_kagerou_adrafinil {
    static let set = AppRecipeSet(
        family: "glass-kagerou-adrafinil",
        githubRules: [
        // Adrafinil — keeps the Mac awake while AI coding agents work. Menu
        // bar app plus two launchd services it registers through
        // SMAppService from its setup window (never at launch): the user
        // LaunchAgent `AdrafinilDaemon` (KeepAlive, holds all policy) and the
        // root LaunchDaemon `AdrafinilHelper` (KeepAlive, runs `pmset`). Both
        // run from inside the bundle (`BundleProgram`), so after a swap they
        // keep the old code until they adopt the new binary themselves: from
        // 1.1 on, each compares its executable's inode/size/mtime with the
        // one it launched from and exits when it changed and nothing is held
        // (daemon: on the app's next connect or the next idle edge; helper:
        // when the restarted daemon probes it), and launchd relaunches it
        // from the new bundle. The vendor's own in-place update relies on
        // exactly that, so a one-click swap needs no gate; a 1.0 copy's
        // services predate it and stay old until logout or reboot
        // (docs/app-audits/glass-kagerou-adrafinil.md, 一键安装).
        //
        // 1.1.1–1.5.4 only say a release is out. From 1.6.0 it also updates
        // itself: Tiptoe over mxcl/AppUpdater reads
        // this repo's /releases, downloads the `Adrafinil-<version>.dmg`,
        // checks the Team ID and swaps the bundle at an idle moment when no
        // agent is being kept awake (auto-install on by default). The
        // prepared install lives in the running process, so a quit drops it.
        //
        // Tags read `v1.13.1` / `v1.9` / `v1.0`, and the short version is the
        // tag's (1.0, 1.9, 1.13.0, 1.13.1 read from the real packages). The
        // pattern reads all 21 tags. Bundle id and Team 52K336H235 are the
        // same from 1.0 to 1.13.1, all notarized, all arm64 only. v1.9 also
        // carries `adrafinil-1.9.0.dmg`, the same bytes as the matching
        // `Adrafinil-1.9.dmg`.
        GitHubReleaseRule(
            bundleID: "glass.kagerou.adrafinil",
            owner: "kageroumado", repo: "adrafinil",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Adrafinil-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
