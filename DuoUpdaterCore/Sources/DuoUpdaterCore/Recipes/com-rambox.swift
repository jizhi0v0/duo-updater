import Foundation

enum com_rambox {
    static let set = AppRecipeSet(
        family: "com-rambox",
        githubRules: [
        // Rambox — Electron workspace browser (ramboxapp/download holds the
        // releases). Its own updater is electron-updater
        // (`app-update.yml`: provider github, this repo, cache dir
        // `rambox-updater`): it checks, downloads only a same-major update by
        // itself (2.7.2's code: a 3.x update is only offered, never
        // auto-downloaded), and installs on quit. The in-app beta toggle reads
        // the `v*-beta.N` prereleases, which this rule leaves out.
        //
        // Two majors share `com.rambox` and Team 7F292FPD69 (2.7.2 and 3.1.2
        // both universal, notarized, macOS 12+). The vendor holds 3.x back:
        // /releases/latest is v2.7.2, published after v3.0.0, and 3.x's
        // `latest-mac.yml` says `stagingPercentage: 0`. This rule follows it, so
        // 2.x copies get 2.x and 3.x copies read up to date until the vendor
        // moves /releases/latest.
        //
        // Tags read `v2.7.2`; the bundle says 2.7.2. Each release carries one
        // `Rambox-<version>-mac.dmg` (universal) next to the `-mac.zip` that
        // electron-updater fetches.
        GitHubReleaseRule(
            bundleID: "com.rambox",
            owner: "ramboxapp", repo: "download",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Rambox-[0-9]+(?:\.[0-9]+)+-mac\.dmg$"#,
            installerKind: .dmg),
        ],
        // One-click never crosses from Rambox 2 to Rambox 3 or later: signing in
        // to Rambox 3 moves the account to the new format one way, and Rambox 2
        // can no longer sign in with it (v3.0.0 notes). Each offer is scoped by
        // the major in its asset name: a 3.x-or-later dmg goes only to a copy
        // that is already 3.x or later, a 2.x dmg only to a 2.x copy. Any other
        // package name is withheld (`unnamedOffer`). Homebrew's `rambox` cask is
        // `auto_updates`, so no Homebrew offer reaches these gates.
        oneClickGates: [
            OneClickGate(
                bundleID: "com.rambox",
                requirement: .installedVersion(pattern: #"^(?:[3-9]|[1-9][0-9]+)\."#),
                reason: "this is Rambox 2 and the update is Rambox 3, which moves your account one way; install Rambox 3 yourself when you are ready to switch",
                offering: #"^GitHub:Rambox-(?:[3-9]|[1-9][0-9]+)\."#),
            OneClickGate(
                bundleID: "com.rambox",
                requirement: .installedVersion(pattern: #"^2\."#),
                reason: "this copy is not Rambox 2 and the update is a Rambox 2 build; update it from Rambox's own updater",
                offering: #"^GitHub:Rambox-2\."#),
        ])
}
