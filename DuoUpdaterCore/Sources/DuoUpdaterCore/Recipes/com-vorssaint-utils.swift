import Foundation

enum com_vorssaint_utils {
    static let set = AppRecipeSet(
        family: "com-vorssaint-utils",
        githubRules: [
        // Vorssaint — Homebrew marks the cask `auto_updates true`, so the generic
        // Homebrew source intentionally skips it. Stable and Beta share both the
        // bundle id and app name; the installed beta's real short version carries
        // `-beta.<N>`, which ReleaseChannel uses to select this pair safely.
        //
        // One-click enabled 2026-09-03 after measuring the artifacts rather than
        // trusting the earlier note. That note said the stable dmg's app failed
        // strict code-sign verification on macOS 27 and used it as the reason to
        // withhold an install spec; on the same OS build (27.0 / 26A5425a) both
        // the stable 3.3.2 and the 3.3.3-beta.3 app pass
        // `codesign --verify --deep --strict` ("valid on disk", "satisfies its
        // Designated Requirement") and `spctl -a -t execute` ("accepted",
        // "Notarized Developer ID", ticket stapled, Team 3D485NHW29). What IS
        // unsigned is the dmg CONTAINER — and `SignatureVerifier` gates on the
        // extracted `.app`, never the container, so it was never the blocker it
        // was read as.
        //
        // Both trains ship exactly one asset per release, and the beta's carries
        // the channel: `Vorssaint-3.3.2.dmg` vs `Vorssaint-3.3.3-beta.3.dmg`. The
        // stable pattern's `[0-9.]+` run refuses the `-` in `-beta.3`, so it
        // cannot match a beta artifact even on the list fallback (which is
        // stable-only anyway); the beta pattern names the suffix outright. The
        // beta pair is registered in `ChannelProofRegistry` — see
        // `ChannelArtifactProof` for why an install-capable non-stable rule
        // without a proof is a hard finding.
        //
        // Verified end to end 2026-09-03 from the beta side, which is the one
        // that can go wrong: installed `3.3.3-beta.1` in `~/Applications`, the
        // row offered `3.3.3-beta.3` and NOT stable 3.3.2 (the display version's
        // `-beta.N` is what `ReleaseChannel.detect` reads — stable and beta share
        // both the bundle id and the app name, so nothing else distinguishes
        // them), and `duo install` landed it on the beta build.
        // Renamed upstream; re-pointed 2026-09-05 (was vorssaintapp/vorssaint-utils).
        // The nightly sweep caught it as `staleSlug` + `anonymousDespiteToken` on both
        // channels (#340, #341): URLSession drops `Authorization` following GitHub's
        // 301, so the rule was silently competing for the anonymous 60/hour per-IP
        // budget. Verified 2026-09-05: `repos/vorssaintapp/vorssaint-utils` answers
        // 301 and `full_name` reads `vorssaint/vorssaint-utils`.
        GitHubReleaseRule(
            bundleID: "com.vorssaint.utils",
            owner: "vorssaint", repo: "vorssaint-utils",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Vorssaint-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        // listPageSize: measured 2026-09-04 — only 4 `-beta.` tags exist in the
        // repo's whole history (73 releases scanned), all consecutive
        // (first-match index 0, worst gap 1). Small sample, so 5 keeps margin
        // rather than trimming to the observed minimum; real page measured at
        // 17 KB, vs 48 KB at the old per_page=20.
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
        // release carries it too (`Vorssaint-3.3.3-beta.3.dmg`). Anchored on the
        // tag segment of the download path rather than a bare `-beta`, for the
        // reason spelled out on VSCodium (`Recipes/com-vscodium.swift`): neither the owner
        // (`vorssaint`, `vorssaintapp` before the 2026-09-05 rename) nor the repo
        // (`vorssaint-utils`) contains the token
        // today, but a proof that could be satisfied by a fixed part of every URL
        // this rule can ever build is a proof that cannot fail. Stable's artifact
        // (`Vorssaint-3.3.2.dmg`, under `/download/v3.3.2/`) fails this pattern,
        // which is the substitution the proof exists to catch — the two trains
        // share the bundle id AND the app name, so the artifact is the only thing
        // that tells them apart after the fact.
        ChannelProofKey("com.vorssaint.utils", .beta):
            .artifact(#"/download/v[0-9.]+-beta\."#),
        ])
}
