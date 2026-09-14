import Foundation

enum org_winehq_wine_staging_wine {
    static let set = AppRecipeSet(
        family: "org-winehq-wine-staging-wine",
        githubRules: [
        // History: docs/app-audits/org-winehq-wine-staging-wine.md#历史与实测
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // Wine (staging) — Gcenx's macOS builds are unsigned, which is what keeps
        // this detection only; the `.tar.xz` they ship in is not the blocker, since
        // `.tarGz` handles that format (see `Recipes/net-pornel-ImageOptim.swift`).
        // Each release tags one upstream version and carries BOTH a `wine-devel-`
        // and a `wine-staging-` tarball, so this rule is safe for the staging
        // bundle id — see the note below for why the stable bundle id gets no rule.
        GitHubReleaseRule(
            bundleID: "org.winehq.wine-staging.wine",
            owner: "Gcenx", repo: "macOS_Wine_builds"),

        // Deliberately NOT covered — Wine (stable), `org.winehq.wine-stable.wine`.
        // The same repo's releases are the devel/staging train while a stable
        // install sits on its own much older line (History has the versions). A
        // rule keyed on `/releases/latest` would tell every stable user that a
        // devel build is their update. Distinguishing the trains needs
        // per-asset filtering (`wine-stable-*`), which a release rule can't express.
        ])
}
