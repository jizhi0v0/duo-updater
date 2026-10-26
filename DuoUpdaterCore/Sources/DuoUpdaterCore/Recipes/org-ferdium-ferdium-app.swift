import Foundation

enum org_ferdium_ferdium_app {
    static let set = AppRecipeSet(
        family: "org-ferdium-ferdium-app",
        githubRules: [
        // Ferdium — Electron messaging-services browser (ferdium/ferdium-app,
        // the Ferdi fork). Its own updater is electron-updater with
        // `provider: github`, which states no address `ElectronManifestSource`
        // may use, so this rule is the route. The app checks 30 s after launch
        // and every hour, downloads on its own into
        // `~/Library/Caches/ferdium-updater/pending/`, and installs only when
        // the user clicks its install button (`autoInstallOnAppQuit = false`).
        // Nothing resident ships in the bundle: the four `Contents/Frameworks`
        // helpers are Electron's own and exit with the app.
        //
        // Tags read `v7.2.3`; the bundle says 7.2.3. Stable reads
        // `/releases/latest`, which skips the flagged prereleases. Every
        // stable release since 6.0.0 has one `Ferdium-mac-<v>-arm64.dmg`
        // (org.ferdium.ferdium-app, Team 55E9FPJ93P, notarized: 6.0.0, 7.2.2,
        // 7.2.3), except v6.5.0 and v6.5.1, which shipped no Mac asset at all
        // (a macOS breakage, per the v6.5.1 notes); the other mac assets are
        // the x64 dmg and the
        // `Ferdium-mac-bundle-*.zip` files electron-updater itself downloads.
        //
        // Nightlies (`v7.2.4-nightly.3`, flagged prerelease, same repo) ship
        // the same bundle id, name and Team, versioned `<v>-nightly.<N>`.
        // `ReleaseChannel.detect` reads that as stable (no step matches a
        // dotted `-nightly.N`), so this rule serves them: a nightly above the
        // newest stable reads up to date, one below it is offered that stable.
        // The gate below keeps one-click off them.
        GitHubReleaseRule(
            bundleID: "org.ferdium.ferdium-app",
            owner: "ferdium", repo: "ferdium-app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Ferdium-mac-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),

        // A copy of one of the 2022–2023 betas (`6.0.0-beta.1` …
        // `6.4.1-beta.2`): same bundle id and Team, but `ReleaseChannel.detect`
        // reads `-beta.N` as beta and the stable rule refuses it (channel-verify
        // read "no source answered" before this rule). There has been no beta
        // since v6.4.1-beta.2; the track continued as nightlies. So a beta
        // copy is shown the newest stable release. Detection-only: a
        // non-stable install needs a channel proof, and only the installed
        // version tells the tracks apart.
        GitHubReleaseRule(
            bundleID: "org.ferdium.ferdium-app",
            owner: "ferdium", repo: "ferdium-app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            channel: .beta),
        ],
        // One-click only for stable copies. A nightly copy (`7.2.4-nightly.3`)
        // reads as stable above; the stable dmg would take it off the nightly
        // track, and its own updater (with Ferdium's "beta" setting on) moves
        // it to the next nightly instead.
        oneClickGates: [
            OneClickGate(
                bundleID: "org.ferdium.ferdium-app",
                requirement: .installedVersion(pattern: #"^[0-9]+(?:\.[0-9]+)+$"#),
                reason: "this is a Ferdium nightly or beta build; update it from Ferdium's own updater"),
        ])
}
