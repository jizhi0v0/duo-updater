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
        ])
}
