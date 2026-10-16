import Foundation

enum net_mullvad_mullvadbrowser {
    static let set = AppRecipeSet(
        family: "net-mullvad-mullvadbrowser",
        githubRules: [
        // History: docs/app-audits/net-mullvad-mullvadbrowser.md#历史与实测
        // Mullvad Browser (mullvad/mullvad-browser) — built by the Tor Project
        // (Team MADPSAYN6T, notarized, universal), the same Mozilla updater
        // family as Tor Browser. No SUFeedURL; its own updater reads
        // `cdn.mullvad.net/browser/update_responses/update_1/…`, whose
        // `detailsURL` is this repo's release page, so the GitHub release is the
        // vendor's own changelog surface and the dmg is the one its download
        // page links to.
        //
        // Two tracks, two bundle ids. Stable is `net.mullvad.mullvadbrowser`,
        // tagged with a bare version (`15.0.25`, `15.0`); Alpha ships as
        // "Mullvad Browser Alpha.app", `net.mullvad.mullvadbrowseralpha`,
        // tagged `16.0a13` and flagged prerelease. The installed
        // CFBundleShortVersionString equals the tag on both tracks, the `a<N>`
        // kept. The stable pattern is anchored so an alpha tag never reads as
        // stable; `/releases/latest` already skips prereleases.
        GitHubReleaseRule(
            bundleID: "net.mullvad.mullvadbrowser",
            owner: "mullvad", repo: "mullvad-browser",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^mullvad-browser-macos-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),

        // Mullvad Browser Alpha — its own bundle id, detected as `.alpha` from
        // the "Alpha" in its name and the `a<N>` in its version. The list is
        // newest-first and alphas interleave with stable releases; the pattern
        // takes only `<maj>.<min>[.<patch>]a<N>` tags.
        GitHubReleaseRule(
            bundleID: "net.mullvad.mullvadbrowseralpha",
            owner: "mullvad", repo: "mullvad-browser",
            usePrereleases: true,
            versionPattern: #"^([0-9]+\.[0-9]+(?:\.[0-9]+)?a[0-9]+)$"#,
            installAssetPattern: #"^mullvad-browser-macos-[0-9]+\.[0-9]+(?:\.[0-9]+)?a[0-9]+\.dmg$"#,
            installerKind: .dmg,
            channel: .alpha),
        ],
        githubChannelProofs: [
        // The alpha asset names its track in both the tag segment and the
        // filename: `…/download/16.0a13/mullvad-browser-macos-16.0a13.dmg`.
        ChannelProofKey("net.mullvad.mullvadbrowseralpha", .alpha):
            .artifact(#"/download/[0-9.]+a[0-9]+/mullvad-browser-macos-[0-9.]+a[0-9]+\.dmg$"#),
        ])
}
