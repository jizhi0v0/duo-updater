import Foundation

enum org_winehq_wine_staging_wine {
    static let set = AppRecipeSet(
        family: "org-winehq-wine-staging-wine",
        githubRules: [
        // Wine (staging) — Gcenx's macOS builds are unsigned, and ship as `.tar.xz`,
        // which the installer doesn't unpack. Detection only. Each release tags one
        // upstream version and carries BOTH a `wine-devel-` and a `wine-staging-`
        // tarball, so this rule is safe for the staging bundle id — see the note
        // below for why the stable bundle id gets no rule.
        GitHubReleaseRule(
            bundleID: "org.winehq.wine-staging.wine",
            owner: "Gcenx", repo: "macOS_Wine_builds"),

        // Deliberately NOT covered — Wine (stable), `org.winehq.wine-stable.wine`.
        // The same repo's releases are the devel/staging train (11.15 on
        // 2026-08-16) while a stable install sits on its own much older line
        // (11.0_1). A rule keyed on `/releases/latest` would tell every stable user
        // that a devel build is their update. Distinguishing the trains needs
        // per-asset filtering (`wine-stable-*`), which a release rule can't express.
        ])
}
