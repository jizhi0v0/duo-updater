import Foundation

enum io_rancherdesktop_app {
    static let set = AppRecipeSet(
        family: "io-rancherdesktop-app",
        githubRules: [
        // Deliberately NOT covered — Wine (stable), `org.winehq.wine-stable.wine`.
        // The same repo's releases are the devel/staging train (11.15 on
        // 2026-08-16) while a stable install sits on its own much older line
        // (11.0_1). A rule keyed on `/releases/latest` would tell every stable user
        // that a devel build is their update. Distinguishing the trains needs
        // per-asset filtering (`wine-stable-*`), which a release rule can't express.

        // Deliberately NOT covered — WezTerm (`com.github.wez.wezterm`). Its
        // Info.plist reports a placeholder `0.1.0` for every build while releases are
        // tagged by timestamp (`20240203-110809-5046fc22`). There is no pair of
        // strings to compare, so any rule here would either be silent or permanently
        // claim an update.

        // Deliberately NOT covered — Maestro (`com.maestro.app`). The repo's recent
        // releases are all `cli-<ver>` (the CLI, now at 2.x) while the desktop app's
        // last `v<ver>` tag is 0.17.3 and no longer appears in the newest 60
        // releases. `/releases/latest` today resolves to `cli-2.8.0`, so a rule keyed
        // on this repo would report the CLI's version as the app's. Revisit if the
        // desktop app resumes its own release train.

        // Deliberately NOT covered — ungoogled-chromium. Its builds carry the SAME
        // bundle id as upstream Chromium (`org.chromium.Chromium`) and a version
        // string in the same shape, so a rule keyed on that id would offer
        // ungoogled builds to a plain Chromium install (and vice versa) with nothing
        // in the version to tell the two trains apart. Revisit only with a signal
        // that distinguishes the builds on disk.

        // MARK: - 2026-08-16, second pass
        //
        // These five reached the earlier sweep's "unclassified" pile only because
        // their artifact was too big to download that day — nothing about them is
        // hard. Each line below again states what was read off the very asset the
        // pattern selects, on a mounted copy of the real download.

        // Rancher Desktop — io.rancherdesktop.app, Team 2Q6FHJR3H3, notarized.
        // The release also ships a `-mac.aarch64.zip`; the dmg is the cask's choice
        // and the one verified here.
        GitHubReleaseRule(
            bundleID: "io.rancherdesktop.app",
            owner: "rancher-sandbox", repo: "rancher-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Rancher\.Desktop-[0-9.]+\.aarch64\.dmg$"#,
            installerKind: .dmg),
        ])
}
