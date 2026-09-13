import Foundation

enum org_keepassxc_keepassxc {
    static let set = AppRecipeSet(
        family: "org-keepassxc-keepassxc",
        githubRules: [
        // KeePassXC — arm64 and x86_64 dmgs ship together; pin arm64. Patch respins
        // append a revision to the FILENAME but not the tag (`KeePassXC-2.7.11-1-
        // arm64.dmg` under tag `2.7.11`), so the version part of the pattern stays
        // loose while the arch stays anchored.
        //
        // Caveat, stated plainly because the tests cannot close it: a respun release
        // keeps BOTH files (tag 2.7.11 ships `-2.7.11-1-arm64.dmg` AND
        // `-2.7.11-arm64.dmg`), so the pattern matches more than one asset and
        // `installableAsset` — first arch-native match wins — is settled by whatever
        // order GitHub happens to return. That order is undocumented (the Releases
        // API states no sort for assets); what this repo's listings actually show,
        // observed 2026-08-16, is case-insensitive by filename — `keepassxc-2.7.12-
        // src.tar.xz` comes back ahead of `KeePassXC-2.7.12-Win64…`, which plain
        // byte order could never produce. Under both that order and byte order the
        // digit sorts ahead of a letter, so `-1-` comes before the plain name and the
        // respin is what installs — which is what we want, but by observation, not by
        // contract. The same ordering means a SECOND respin would LOSE: `-1-` also
        // sorts before `-2-`, so `-2` would be passed over.
        // `keepassxcRespinIsTheAssetSelected` pins the selection semantics on the
        // real 2.7.11 asset list and records the `-2` case as a known issue, so the
        // gap stays visible instead of looking closed. The blast radius is small and
        // bounded: every candidate is the same version, same Team G2S7P7J672 and
        // notarized, so the worst case is a superseded packaging of the version the
        // user was going to get anyway — never a cross-train swap.
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
