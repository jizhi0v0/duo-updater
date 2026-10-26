import Foundation

enum org_standardnotes_standardnotes {
    static let set = AppRecipeSet(
        family: "org-standardnotes-standardnotes",
        githubRules: [
        // Standard Notes — open-source encrypted notes app (standardnotes/app,
        // Electron). Its own updater is electron-updater with the `github`
        // provider on this same repo (`app-update.yml`, cache dir
        // `@standardnotesinner-desktop-updater`). It never sets
        // `allowPrerelease`, so a numeric version reads /releases/latest, the
        // same release this rule reads. With "automatic updates" on (the
        // default) it downloads the zip in the background and Squirrel installs
        // it when the app quits. No login item or launch agent ships in the
        // bundle; the four `Standard Notes Helper*.app` are Electron's.
        //
        // The repo is a monorepo: desktop, mobile and clipper releases share one
        // Releases list. CI publishes every desktop build as a prerelease
        // (`desktop.release.reuse.yml`, `prerelease: true`) and the vendor
        // promotes some of them by hand; the unpromoted ones are ordinary builds
        // on the same version line, not another track. The only non-desktop
        // releases ever left unflagged are mobile 3.24.0 / 3.24.1 (June 2022),
        // so /releases/latest lands on the newest promoted desktop build, and
        // the vendor's own updater depends on that too. `versionPattern` still
        // names the desktop tag, so a mobile or clipper release that did take
        // /releases/latest would read as no match, never as a version.
        //
        // Tags read `@standardnotes/desktop@3.202.10`; the bundle says 3.202.10.
        // Each release ships arm64 and x64 dmg + zip; DuoUpdater runs only on
        // arm64, so the rule installs `standard-notes-<v>-mac-arm64.dmg`
        // (org.standardnotes.standardnotes, Team HKF9BXSN95, notarized; same id
        // and Team in 3.201.18, 3.202.7 and 3.202.10).
        GitHubReleaseRule(
            bundleID: "org.standardnotes.standardnotes",
            owner: "standardnotes", repo: "app",
            versionPattern: #"^@standardnotes/desktop@([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^standard-notes-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
