import Foundation

enum com_t3tools_t3code {
    static let set = AppRecipeSet(
        family: "com-t3tools-t3code",
        githubRules: [
        // History: docs/app-audits/com-t3tools-t3code.md#历史与实测
        // T3 Code — two trains, ONE bundle id (`com.t3tools.t3code`), one repo.
        // `ReleaseChannel.detect()` reads the display name: the primary build is
        // `T3 Code (Alpha).app` (→ .alpha) and the prerelease train is
        // `T3 Code (Nightly).app` (→ .nightly), verified on the mounted artifacts.
        // Neither carries SUFeedURL; the cask is auto_updates, so Homebrew defers.
        //
        // The alpha train tags plain `vX.Y.Z` and is NOT prerelease-flagged, so
        // `/releases/latest` answers for it; the anchored pattern keeps the
        // nightly tags (same repo) from ever reading as alpha. One-click: the
        // arm64 dmg holds the same notarized `T3 Code (Alpha)` app — Team
        // ARK85ZXQ4Z, verified on the mounted v0.0.36 artifact.
        GitHubReleaseRule(
            bundleID: "com.t3tools.t3code",
            owner: "pingdotgg", repo: "t3code",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^T3-Code-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .alpha),

        // T3 Code nightly — prerelease tags `vX.Y.Z-nightly.<date>.<seq>`, several
        // per day, marked prerelease, so `usePrereleases` reads the list and the
        // pattern is anchored to the nightly shape end to end. The app reports the
        // whole string as BOTH marketing and build, so the extracted version must
        // keep it intact rather than truncate to `X.Y.Z` — a nightly install shows
        // e.g. `0.0.37-nightly.20260830.1227` on both sides, and `VersionComparator`
        // orders the date/seq runs numerically. One-click: same Team
        // ARK85ZXQ4Z, verified on the mounted nightly artifact. The asset name
        // carries `-nightly.` — which is also why the alpha pattern above cannot
        // drift onto this train: its `[0-9.]+` run refuses the dash.
        // listPageSize: releases of this repo's other trains land between two
        // nightly tags, so the newest nightly need not be first in the list. 5 was
        // sized for 2.5x headroom over the widest run measured on 2026-09-04; the
        // 2026-09-14 recheck found a wider run of 4 (History has both, and the
        // page sizes).
        GitHubReleaseRule(
            bundleID: "com.t3tools.t3code",
            owner: "pingdotgg", repo: "t3code",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^T3-Code-[0-9.]+-nightly\.[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .nightly),
        ],
        githubChannelProofs: [
        // T3 Code nightly names its channel in the tag, and GitHub builds the
        // asset URL as `…/download/<tag>/<name>` — so the tag the version
        // pattern matched is in the path.
        ChannelProofKey("com.t3tools.t3code", .nightly):
            .artifact(#"/download/v[0-9.]+-nightly\."#),
        // T3 Code alpha is the one channel with no token in the tag OR the asset
        // name: `v0.0.36` / `T3-Code-0.0.36-arm64.dmg` are byte-identical in
        // shape to what a hypothetical stable train would publish. What keeps
        // the alpha rule off the nightly train is the install pattern's PURE
        // DIGIT run — nightly assets (`T3-Code-0.0.37-nightly.20260830.1227-
        // arm64.dmg`) carry `-nightly.<date>.<seq>` between the version and
        // `-arm64`, which `[0-9.]+` refuses. So the proof is an anchor on that
        // field, not on the artifact: it fails the day someone loosens the
        // pattern enough to match nightly names (e.g. a `.*` run). Nightly was the
        // only other train this repo published when this was written; a
        // `-preview.` train has appeared since, whose asset names `[0-9.]+`
        // refuses the same way (History has the recheck). What it cannot do is
        // catch a vendor-launched stable train with identical naming — nothing in the
        // URL would distinguish it, and `/releases/latest` would return it; the
        // anchor documents that exposure rather than pretending to close it.
        ChannelProofKey("com.t3tools.t3code", .alpha):
            .recipeAnchor(#"\[0-9\.\]\+-arm64"#, in: ["installAssetPattern"]),
        ])
}
