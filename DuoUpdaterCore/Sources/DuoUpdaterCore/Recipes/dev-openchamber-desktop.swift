import Foundation

enum dev_openchamber_desktop {
    static let set = AppRecipeSet(
        family: "dev-openchamber-desktop",
        githubRules: [
        // OpenChamber — electron-builder publishes both architectures beside
        // Windows/Linux/mobile artifacts. Keep the extension and mac token
        // anchored; the architecture-aware selector chooses arm64 or x64.
        // Mounted arm64 dmg: dev.openchamber.desktop, Team 5J7WJGPA2Q, notarized.
        GitHubReleaseRule(
            bundleID: "dev.openchamber.desktop",
            owner: "openchamber", repo: "openchamber",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),

        // Preview — the `v2-preview` GitHub prerelease (`2.0.0-preview.8`), which
        // `ReleaseChannel.detect` step 4 reads as `.preview`. Without a rule of its
        // own the stable rule's channel gate refuses such a copy and it reads
        // unknown. This rule serves it the STABLE release, because that is what
        // the build's own updater does: its `app.asar` sets
        // `autoUpdater.allowPrerelease = false` against the github provider, so a
        // preview copy is offered the newest stable release and nothing else.
        //
        // Byte-identical to the stable rule apart from `channel`, and every field
        // that keeps the preview prerelease out is the stable one: no
        // `usePrereleases`, so it reads `/releases/latest`, which GitHub computes
        // without prereleases (and `stableOnly` when it falls back to the list);
        // a tag pattern that ends at the dotted number, so neither `v2-preview`
        // nor a `-preview.<N>` tag can match; and an asset pattern whose version
        // is digits and dots only, so `OpenChamber-2.0.0-preview.8-mac-*.dmg`
        // cannot match either.
        //
        // So the only builds this rule can hand anyone are the ones the stable
        // rule hands a stable copy. Once a preview copy takes one, it reads
        // stable and the stable rule serves it.
        GitHubReleaseRule(
            bundleID: "dev.openchamber.desktop",
            owner: "openchamber", repo: "openchamber",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg,
            channel: .preview),
        ],
        githubChannelProofs: [
        // The preview rule resolves stable's artifact by design, so an `.artifact`
        // proof would have to assert the absence of a channel token, which is not
        // what that case means and is not what its finding would say. Same reason
        // WhatCable's, CotEditor's and Cindy's anchors exist, from the other side:
        // theirs keep a beta rule able to read prereleases; this one keeps a
        // preview rule UNABLE to. Three fields, one branch each, none able to
        // satisfy another:
        //   • `usePrereleases` must stay `false` (`/releases/latest`);
        //   • `versionPattern` must close its capture right after the dotted
        //     number and end there (`…[0-9]+)+)$`), so no suffix is accepted;
        //   • `installAssetPattern` must keep the version as `[0-9.]+` directly
        //     before `-mac-`, so a `-preview.<N>` filename cannot match.
        // Loosening any one of them fails the proof in a PR. It cannot see the
        // vendor publishing a preview as a non-prerelease with a plain tag; then
        // the stable rule would take it too.
        ChannelProofKey("dev.openchamber.desktop", .preview):
            .recipeAnchor(
                #"^false$|\[0-9\]\+\)\+\)\$$|^\^OpenChamber-\[0-9\.\]\+-mac-"#,
                in: ["usePrereleases", "versionPattern", "installAssetPattern"]),
        ])
}
