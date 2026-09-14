import Foundation

enum net_ankiweb_anki {
    static let set = AppRecipeSet(
        family: "net-ankiweb-anki",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/net-ankiweb-anki.md#历史与实测
        // Anki — tags are date-shaped with a zero-padded month (e.g. `26.08.1`)
        // while the app reports `26.8.1`. That is NOT a mismatch for us: `VersionComparator`
        // compares digit runs numerically, so 08 == 8 and the two read as the same
        // version — no phantom update.
        //
        // Apple-silicon and Intel dmgs ship together, and BOTH are in the pattern:
        // `-mac-apple` carries no token that `installableAsset` recognises as an
        // architecture, so on its own it reads as arch-neutral. With both matched
        // the arch preference picks between them — `intel` marks the other dmg as
        // the x86_64 build, and the token-free `-mac-apple` wins on Apple silicon,
        // the only host DuoUpdater runs on (`App/project.yml`);
        // `GitHubReleaseRuleTests.archNeutralNamesStillResolvePerArchitecture` pins
        // that choice. Whatever a name says, the install gate reads the downloaded
        // bundle's real architectures (`SignatureVerifier.verifyRunnableArchitecture`).
        // Team ZL66D3NMZM and notarization verified on BOTH dmgs.
        //
        // CLOSED GAP (verified 2026-08-16, and was never a rule bug): Anki stamps
        // `CFBundleVersion` as a literal "1" for every build. When
        // the installed short version has no patch component (26.08 → app reports
        // "26.8"), `UpdateChecker.evaluate`'s "vendor folded the build into the
        // version" fallback rebuilt it as "26.8" + "1" = "26.8.1" and concluded the
        // app was already current — hiding exactly the x.y → x.y.1 patch. Every
        // other step (26.8.1 → 26.9) always reported normally.
        //
        // Fixed in the shared logic rather than here, as this note said it would
        // have to be: that fallback now demands the remote EQUAL the rebuilt string
        // and the installed build be a counter of at least 100 — a vendor folds a
        // build in because it is a large counter (Oray's 30757), so a hand-stamped
        // "1" is evidence against the folded reading. Pinned by
        // `evaluateFoldingIgnoresBuildsTooSmallToBeFoldedCounters`, whose first case
        // is this one.
        // One-click: net.ankiweb.anki, Team ZL66D3NMZM, notarized.
        GitHubReleaseRule(
            bundleID: "net.ankiweb.anki",
            owner: "ankitects", repo: "anki",
            installAssetPattern: #"^anki-[0-9.]+-mac-(apple|intel)\.dmg$"#,
            installerKind: .dmg),
        ])
}
