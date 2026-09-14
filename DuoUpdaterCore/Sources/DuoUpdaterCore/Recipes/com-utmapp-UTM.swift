import Foundation

enum com_utmapp_UTM {
    static let set = AppRecipeSet(
        family: "com-utmapp-UTM",
        changelogs: [
        // History: docs/app-audits/com-utmapp-UTM.md#历史与实测
        // UTM Stable and Beta publish in one GitHub repository with plain numeric
        // tags and the same `UTM.dmg` asset name. The release record's
        // `prerelease` bit is the only split, matching the corresponding
        // GitHubReleaseRule. Two channel-keyed recipes over the same JSON keep the
        // histories apart: Stable never shows the v5 previews.
        //
        // The Beta recipe is NOT the mirror image, and that asymmetry is the
        // point: UTM's previews graduate into the same numbering (`v4.7.0…v4.7.3`
        // are "(Beta)", `v4.7.4`/`v4.7.5` are not), so a preview install is
        // legitimately offered a release the `prerelease` bit calls stable — and
        // `includesPromotedStable` is what stops that update's notes from
        // rendering as an empty panel. See `GitHubCandidateScope`.
        ChangelogRecipe(
            bundleID: "com.utmapp.UTM",
            source: URL(
                string: "https://api.github.com/repos/utmapp/UTM/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "com.utmapp.UTM",
            source: URL(
                string: "https://api.github.com/repos/utmapp/UTM/releases?per_page=40")!,
            mode: .json,
            // 40, not stable's 20: this side reads BOTH kinds out of one 40-entry
            // page, so a 20-entry cap would spend part of the window on releases
            // the preview history is not about — and the entry pushed out first is
            // the graduated one an install is actually being offered, which is the
            // whole reason this recipe keeps final releases (History has the
            // measured positions and margins).
            maxEntries: 40,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // UTM — virtualiser. Stable and Beta share EVERYTHING visible locally:
        // bundle id, app name, plain numeric marketing/build versions, Team ID,
        // and the literal `UTM.dmg` asset name. The tag is plain numeric too
        // (e.g. `v5.0.5`), so no suffix can gate the beta rule. Instead, the source
        // looks up the exact tag for the installed version and reads GitHub's own
        // authoritative `prerelease` bit to decide WHICH RULE this copy is on. An
        // unprovable tag claims no channel and answers on the stable rule.
        //
        // What that bit does NOT mean here is "a parallel Beta train": each minor
        // line ships previews and then graduates at a higher patch number
        // (`v4.7.0…v4.7.3` are "(Beta)", `v4.7.4`/`v4.7.5` are not). Confining a
        // preview install to prereleases therefore strands it at every graduation,
        // while offering it the newest release of any kind walks a `v4.7.3`
        // install onto a `v5.0.5` preview instead of its own line's `v4.7.5`.
        // Hence the line-anchored scope. (History has the release counts and the
        // graduations measured over the whole history.)
        //
        // One-click: the `UTM.dmg` asset holds com.utmapp.UTM, Team WDNLXAD4W8,
        // strict deep signature valid, Gatekeeper `accepted, source=Notarized
        // Developer ID` (checked on a real DMG 2026-09-03; History has its version,
        // size and hash).
        GitHubReleaseRule(
            bundleID: "com.utmapp.UTM",
            owner: "utmapp", repo: "UTM",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^UTM\.dmg$"#,
            installerKind: .dmg),

        // listPageSize deliberately left at the 20 default — do NOT copy the
        // "first-match index 0" number from the stable rule above or from any
        // simple per-repo table: `.installedMajorLineOrNewestStable` doesn't
        // walk for the first tag match, it needs `lineAnchoredCeiling` to find
        // EITHER the newest release in the installed major line OR the newest
        // STABLE release within the fetched page (whichever's newer) — missing
        // both makes it decline rather than offer anything. Counting stable by
        // GitHub's own `prerelease` bit (not the version pattern, which nearly
        // every tag matches): during a preview burst the newest STABLE release
        // sits several entries down, and consecutive stable releases have sat
        // nearly 10 entries apart in the newest 100 (when checked, 2026-09-04 and
        // 2026-09-14; History has the positions and the pairs). A page of 20
        // covers both; trimming it below ~15 would be gambling on the burst
        // never growing past what's been observed once already.
        GitHubReleaseRule(
            bundleID: "com.utmapp.UTM",
            owner: "utmapp", repo: "UTM",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            candidateScope: .installedMajorLineOrNewestStable,
            installedTagPrefix: "v",
            installAssetPattern: #"^UTM\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // UTM's tag and asset name carry no channel token at all (e.g. `v5.0.5` /
        // `UTM.dmg`), and — unlike every other key here — its Beta artifact is not
        // even meant to be a different artifact forever: UTM's previews graduate
        // into the same numbering, so a Beta install is legitimately offered a
        // release GitHub marks stable (see `GitHubCandidateScope`). The thing that
        // must not drift is therefore not "which train the file came from" but
        // WHICH ALGORITHM chose it, and that is what this anchors: the rule must
        // keep asking for the line-anchored candidate.
        //
        // Be clear about the reach of that: a `.recipeAnchor` reflects the
        // REGISTRY's field values, so it fails when someone edits this rule back
        // to `.newest`, and it cannot see anything about the code in `resolve`
        // that reads the field.
        // `UTMGitHubChannelTests.aPreviewInstallWhoseLineGraduatedIsOfferedThatGraduation`
        // is what covers the code: delete the ceiling and it offers a v5 preview
        // to a 4.7 install.
        ChannelProofKey("com.utmapp.UTM", .beta):
            .recipeAnchor(#"^installedMajorLineOrNewestStable$"#, in: ["candidateScope"]),
        ])
}
