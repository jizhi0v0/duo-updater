import Foundation

enum org_xquartz_X11 {
    static let set = AppRecipeSet(
        family: "org-xquartz-X11",
        githubRules: [
        // History: docs/app-audits/org-xquartz-X11.md#历史与实测
        // XQuartz — ships as a pkg, so this takes the system-installer route the
        // Office/AweSun packages use (`UpdatePolicy.requiresInstaller` already
        // covers `"GitHub"` + `.pkg`): we download the official package and hand it
        // to macOS, which prompts for the administrator password itself. Nothing
        // here swaps a bundle — X11 installs far more than `XQuartz.app`
        // (`/opt/X11`, launchd jobs), and an in-place app swap would leave all of
        // it stale.
        //
        // The installed app lives in `/Applications/Utilities`, which the scanner
        // covers. On the real pkg, `pkgutil --check-signature` reports "Developer
        // ID Installer: Apple Inc. - XQuartz (NA574AWV7E)", notarized and
        // timestamped, and its `Distribution` declares `org.xquartz.X11` — the same
        // id the installed bundle reports — at the version its tag names (checked
        // 2026-08-16; History has the pkg version and size).
        //
        // Tags are `XQuartz-2.8.6`; the release also carries `.dSYMS.tar.bz2` and
        // `.sha256sum`/`.sha512sum` siblings, so the asset pattern is anchored to
        // the exact pkg name rather than "the first thing that looks like a build".
        GitHubReleaseRule(
            bundleID: "org.xquartz.X11",
            owner: "XQuartz", repo: "XQuartz",
            versionPattern: #"^XQuartz-([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^XQuartz-[0-9.]+\.pkg$"#,
            installerKind: .pkg),
        ])
}
