import Foundation

enum org_keepassxc_keepassxc {
    static let set = AppRecipeSet(
        family: "org-keepassxc-keepassxc",
        githubRules: [
        // History: docs/app-audits/org-keepassxc-keepassxc.md#历史与实测
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // KeePassXC — arm64 and x86_64 dmgs ship together; pin arm64. Patch respins
        // append a revision to the FILENAME but not the tag (`KeePassXC-2.7.11-1-
        // arm64.dmg` under tag `2.7.11`), so the version part of the pattern stays
        // loose while the arch stays anchored.
        //
        // A respun release keeps BOTH files (tag 2.7.11 ships `-2.7.11-1-arm64.dmg`
        // AND `-2.7.11-arm64.dmg`), so the pattern matches more than one asset.
        // `installableAsset` does not settle that by the order GitHub returns
        // (the Releases API states no sort for assets): among the arch-native
        // matches it takes the filename that ranks highest under
        // `VersionComparator`, so the respin beats the original and a SECOND
        // respin would beat the first, whichever way the listing arrives.
        // `keepassxcRespinIsTheAssetSelected` pins that on the real 2.7.11 asset
        // list, on a `-2` respin listed in either order, and on `-9` against `-10`.
        // The blast radius of a wrong pick would be small and bounded anyway: every
        // candidate is the same version, same Team G2S7P7J672 and notarized, so the
        // worst case is a superseded packaging of the version the user was going to
        // get anyway — never a cross-train swap.
        // One-click: org.keepassxc.keepassxc, Team G2S7P7J672, notarized.
        //
        // If a snapshot-channel rule is ever added for this bundle id: no
        // `installAssetPattern`/`installerKind` — snapshot ships completely
        // unsigned (docs/app-audits/org-keepassxc-keepassxc.md, #95).
        GitHubReleaseRule(
            bundleID: "org.keepassxc.keepassxc",
            owner: "keepassxreboot", repo: "keepassxc",
            installAssetPattern: #"^KeePassXC-[0-9.\-]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
