import Foundation

enum digital_twisted_noTunes {
    static let set = AppRecipeSet(
        family: "digital-twisted-noTunes",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // noTunes — tags are `vX.Y` (two components), which the default pattern
        // handles. One-click: digital.twisted.noTunes, Team JP6WW46Y42, notarized.
        //
        // Carried the same latent shape as Anki (see the batch header): the app
        // reports `CFBundleShortVersionString` 3.5 with `CFBundleVersion` 1, so a
        // three-component `v3.5.1` tag would have had `evaluate`'s folded-build
        // fallback rebuild the installed side as "3.5.1" and call it current. That
        // is closed with Anki's: a build of 1 is below the fallback's counter
        // floor, so this rule is no longer waiting on upstream to keep tagging two
        // components.
        GitHubReleaseRule(
            bundleID: "digital.twisted.noTunes",
            owner: "tombonez", repo: "noTunes",
            installAssetPattern: #"^noTunes-[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
