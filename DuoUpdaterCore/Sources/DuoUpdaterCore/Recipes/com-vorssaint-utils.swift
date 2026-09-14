import Foundation

enum com_vorssaint_utils {
    static let set = AppRecipeSet(
        family: "com-vorssaint-utils",
        githubRules: [
        // History: docs/app-audits/com-vorssaint-utils.md#历史与实测
        // Vorssaint — Homebrew marks the cask `auto_updates true`, so the generic
        // Homebrew source intentionally skips it. Stable and Beta share both the
        // bundle id and app name; the installed beta's real short version carries
        // `-beta.<N>`, which ReleaseChannel uses to select this pair safely.
        //
        // One-click (enabled 2026-09-03): when checked that day, both trains' apps
        // passed `codesign --verify --deep --strict` and `spctl -a -t execute`
        // ("Notarized Developer ID", ticket stapled, Team 3D485NHW29). What IS
        // unsigned is the dmg CONTAINER — and `SignatureVerifier` gates on the
        // extracted `.app`, never the container, so an unsigned container is not a
        // blocker (History has the versions measured and the earlier note this
        // overturned).
        //
        // Both trains ship exactly one asset per release, and the beta's carries
        // the channel: e.g. `Vorssaint-3.3.2.dmg` vs `Vorssaint-3.3.3-beta.3.dmg`.
        // The stable pattern's `[0-9.]+` run refuses the `-` in `-beta.3`, so it
        // cannot match a beta artifact even on the list fallback (which is
        // stable-only anyway); the beta pattern names the suffix outright. The
        // beta pair is registered in `ChannelProofRegistry` — see
        // `ChannelArtifactProof` for why an install-capable non-stable rule
        // without a proof is a hard finding.
        //
        // The beta side is the one that can go wrong, and it was verified end to
        // end: a beta install was offered the newer beta and NOT the stable
        // release, and `duo install` landed it on the beta build (History has the
        // dated run).
        // Renamed upstream; re-pointed 2026-09-05 (was vorssaintapp/vorssaint-utils).
        // The canonical slug is pinned on purpose: URLSession drops `Authorization`
        // following GitHub's 301 from the old slug, so the rule would silently
        // compete for the anonymous 60/hour per-IP budget (History has how the
        // nightly sweep caught it, and the check of the redirect).
        GitHubReleaseRule(
            bundleID: "com.vorssaint.utils",
            owner: "vorssaint", repo: "vorssaint-utils",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Vorssaint-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        // listPageSize: `-beta.` tags are rare in this repo and have shipped
        // consecutively, but stable releases published after a beta run push the
        // newest beta tag down the list. When checked (2026-09-14) it sat at index
        // 3 of a page of 5, so the page still holds it after one more stable
        // release and not after two without a new beta. 5 was sized on 2026-09-04,
        // before those stable releases (History has both measurements and the
        // page sizes).
        GitHubReleaseRule(
            bundleID: "com.vorssaint.utils",
            owner: "vorssaint", repo: "vorssaint-utils",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$"#,
            installAssetPattern: #"^Vorssaint-[0-9.]+-beta\.[0-9]+\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Vorssaint beta names its channel in the tag, and the single asset per
        // release carries it too (e.g. `Vorssaint-3.3.3-beta.3.dmg`). Anchored on the
        // tag segment of the download path rather than a bare `-beta`, for the
        // reason spelled out on VSCodium (`Recipes/com-vscodium.swift`): neither the owner
        // (`vorssaint`, `vorssaintapp` before the 2026-09-05 rename) nor the repo
        // (`vorssaint-utils`) contains the token
        // today, but a proof that could be satisfied by a fixed part of every URL
        // this rule can ever build is a proof that cannot fail. Stable's artifact
        // (e.g. `Vorssaint-3.3.2.dmg`, under `/download/v3.3.2/`) fails this pattern,
        // which is the substitution the proof exists to catch — the two trains
        // share the bundle id AND the app name, so the artifact is the only thing
        // that tells them apart after the fact.
        ChannelProofKey("com.vorssaint.utils", .beta):
            .artifact(#"/download/v[0-9.]+-beta\."#),
        ])
}
