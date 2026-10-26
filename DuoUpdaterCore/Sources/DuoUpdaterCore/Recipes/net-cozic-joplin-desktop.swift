import Foundation

enum net_cozic_joplin_desktop {
    static let set = AppRecipeSet(
        family: "net-cozic-joplin-desktop",
        githubRules: [
        // Joplin — open-source note-taking app (laurent22/joplin, Electron).
        // On macOS its own updater only notifies: `checkForUpdates.ts` reads
        // objects.joplinusercontent.com/r/releases (a mirror of this repo's
        // release list), shows a dialog and opens the dmg URL in the browser.
        // The bundle also carries electron-updater (`app-update.yml`,
        // Squirrel.framework), but `app.ts` turns
        // `featureFlag.autoUpdaterServiceEnabled` off on every Mac launch, so
        // nothing downloads or swaps the bundle behind us.
        //
        // The repo is a monorepo: releases are `v<x.y.z>` (desktop) plus six
        // 2018 `android-v…` ones; server/cli/ios/clipper are tags without
        // releases. Every stable release since v2.12.15 carries one
        // `Joplin-<v>-arm64.DMG` (upper-case extension; only a few 2.12
        // prereleases used `.dmg`) next to an x86_64 `Joplin-<v>.dmg`,
        // `-arm64.pkg`/`.zip` and `-mac.zip`.
        // net.cozic.joplin-desktop, Team A9BXAFS6CT, notarized; same id and
        // Team back to v0.10.19 (2017).
        //
        // Prereleases share the tag shape, the asset names and the bundle id
        // (217 of 417 `v` releases); the in-app "Get pre-releases when
        // checking for updates" setting picks them. This rule reads
        // /releases/latest only: a prerelease copy newer than stable reads as
        // up to date, and one behind stable is offered the stable release,
        // as Joplin's own check would.
        GitHubReleaseRule(
            bundleID: "net.cozic.joplin-desktop",
            owner: "laurent22", repo: "joplin",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Joplin-[0-9]+(?:\.[0-9]+)+-arm64\.DMG$"#,
            installerKind: .dmg),
        ])
}
