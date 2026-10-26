import Foundation

enum pro_affine_app {
    static let set = AppRecipeSet(
        family: "pro-affine-app",
        githubRules: [
        // AFFiNE — open-source docs/whiteboard/database workspace
        // (toeverything/AFFiNE, an Electron Forge monorepo). Three tracks, each
        // its own app and bundle id (`appIdMap` in
        // packages/frontend/apps/electron/scripts/make-env.ts): stable
        // `pro.affine.app` "AFFiNE", beta `pro.affine.beta` "AFFiNE-beta", canary
        // `pro.affine.canary` "AFFiNE-canary". All Team 73YMMDVT2M, notarized.
        //
        // Its own updater is electron-updater 6.8.9 with a custom provider: it
        // asks affine.pro/api/worker/releases?channel=<track> (the newest of the
        // repo's first page of releases on that track), downloads the
        // `-macos-<arch>.zip` into ~/Library/Caches/AFFiNE/pending, and hands it
        // to Squirrel.Mac only when the user picks restart (`autoInstallOnAppQuit`
        // is false). No helper outside the Electron Helper apps, no login item.
        //
        // Stable: tags read `v0.27.4`, the bundle says 0.27.4. Every
        // non-prerelease tag since v0.6.0 is `v<x.y.z>`; betas and canaries are
        // flagged prerelease, so /releases/latest is the stable desktop release.
        // One arm64 dmg per release (`affine-<v>-stable-macos-arm64.dmg`); the
        // x64 dmg and both zips are left out.
        GitHubReleaseRule(
            bundleID: "pro.affine.app",
            owner: "toeverything", repo: "AFFiNE",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^affine-[0-9]+(?:\.[0-9]+)+-stable-macos-arm64\.dmg$"#,
            installerKind: .dmg),

        // Beta (`pro.affine.beta`): tags `v0.27.5-beta.1`, the bundle says
        // 0.27.5-beta.1, so the capture keeps the suffix. The vendor's beta
        // updater offers only beta builds, and so does this rule. Daily canaries
        // sit between betas: on 2026-10-26 the newest beta was 26th in the list
        // (since 2025, two betas had sat at most 14 places apart). listPageSize
        // 50 holds about twice that 26; a beta older than the page reads as
        // unknown, not as a wrong version.
        GitHubReleaseRule(
            bundleID: "pro.affine.beta",
            owner: "toeverything", repo: "AFFiNE",
            usePrereleases: true,
            listPageSize: 50,
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$"#,
            installAssetPattern: #"^affine-[0-9]+(?:\.[0-9]+)+-beta\.[0-9]+-beta-macos-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),

        // Canary (`pro.affine.canary`): tags `v2026.10.25-canary.907` since
        // 2026-03 (`v0.23.0-canary.2` before), the bundle says
        // 2026.10.25-canary.907. A canary is almost always the newest release;
        // the widest run of betas/stables between two dated canaries was 12.
        GitHubReleaseRule(
            bundleID: "pro.affine.canary",
            owner: "toeverything", repo: "AFFiNE",
            usePrereleases: true,
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+-canary\.[0-9]+)$"#,
            installAssetPattern: #"^affine-[0-9]+(?:\.[0-9]+)+-canary\.[0-9]+-canary-macos-arm64\.dmg$"#,
            installerKind: .dmg,
            channel: .canary),
        ],
        githubChannelProofs: [
        // The tag and the file name both name the track:
        // `…/download/v0.27.5-beta.1/affine-0.27.5-beta.1-beta-macos-arm64.dmg`.
        ChannelProofKey("pro.affine.beta", .beta):
            .artifact(#"/download/v?[0-9.]+-beta\.[0-9]+/affine-[0-9.]+-beta\.[0-9]+-beta-macos-arm64\.dmg$"#),
        // `…/download/v2026.10.25-canary.907/affine-2026.10.25-canary.907-canary-macos-arm64.dmg`.
        ChannelProofKey("pro.affine.canary", .canary):
            .artifact(#"/download/v?[0-9.]+-canary\.[0-9]+/affine-[0-9.]+-canary\.[0-9]+-canary-macos-arm64\.dmg$"#),
        ])
}
