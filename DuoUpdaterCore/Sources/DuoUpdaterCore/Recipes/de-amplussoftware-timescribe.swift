import Foundation

enum de_amplussoftware_timescribe {
    static let set = AppRecipeSet(
        family: "de-amplussoftware-timescribe",
        githubRules: [
        // TimeScribe — open-source time tracker (WINBIGFOX/TimeScribe), a
        // NativePHP app: Laravel run by a bundled PHP inside Electron. Its own
        // updater is electron-updater with `provider: github`, which states no
        // address `ElectronManifestSource` may use, so this rule is the route.
        // That updater checks at launch and every two hours, downloads on its
        // own (`autoDownload` is left at its default), and installs on quit;
        // with the app's "auto update" setting on (the default) it also quits
        // and installs by itself once no window is open (`app:check-can-install`,
        // every five minutes). The four nested apps are Electron's helpers.
        //
        // Tags read `v1.17.1`; the bundle says 1.17.1. The pattern leaves out
        // the flagged `v1.2.0-beta.1`…`beta.3` (the beta rule below serves
        // those copies) and the release-less tag `v1.1.2-dev`.
        //
        // `TimeScribe-<v>-arm64.dmg` is de.amplussoftware.timescribe, Team
        // 69A277BV6W, notarized (1.17.1, 1.17.0, 1.2.0-beta.3; 0.1.0 has the
        // same id and Team). The
        // `-x64` dmg/zip are the Intel build; there is no universal.
        GitHubReleaseRule(
            bundleID: "de.amplussoftware.timescribe",
            owner: "WINBIGFOX", repo: "TimeScribe",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^TimeScribe-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),

        // A copy of `1.2.0-beta.1`…`beta.3` (2025-05, flagged prerelease):
        // same bundle id, but its version makes `ReleaseChannel.detect` call it
        // beta, and the stable rule refuses it; without this rule channel-verify
        // reads "no source answered". There has been no prerelease since
        // `v1.2.0` (2025-05-18), so the release such a copy moves to is the
        // newest stable one: same tags, read from `/releases/latest`.
        //
        // Detection-only: a non-stable install needs a channel proof, and only
        // the installed version tells the two tracks apart.
        GitHubReleaseRule(
            bundleID: "de.amplussoftware.timescribe",
            owner: "WINBIGFOX", repo: "TimeScribe",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            channel: .beta),
        ])
}
