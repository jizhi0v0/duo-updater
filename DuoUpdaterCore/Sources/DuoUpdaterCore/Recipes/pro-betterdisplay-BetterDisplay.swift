import Foundation

enum pro_betterdisplay_BetterDisplay {
    static let set = AppRecipeSet(
        family: "pro-betterdisplay-BetterDisplay",
        changelogs: [
        // History: docs/app-audits/pro-betterdisplay-BetterDisplay.md#历史与实测
        // BetterDisplay — the same GitHub release bodies the vendor's own page was
        // already showing, rendered natively instead of in a web view.
        //
        // The appcast carries no `<description>`; every item points
        // `<sparkle:releaseNotesLink>` at
        // `waydabber.github.io/BetterDisplay/changelog.html?tag=<tag>`. That page is
        // an EMPTY shell with no body content at all (checked 2026-08-27 and
        // 2026-09-14; History has the size). Its inline script reads `?tag`, GETs
        // `api.github.com/repos/waydabber/BetterDummy/releases/tags/<tag>` (the old
        // repo name, still redirecting) and renders `response.body` with marked.js.
        // So the web view was rendering GitHub markdown the whole time, minus our
        // styling and plus the vendor's "Download app for macOS" button image. Going
        // to the API directly gets the identical text, the version and date headings
        // the shell never had, and the history a per-tag page cannot hold.
        //
        // THREE recipes, one per track — none of them removable as a duplicate,
        // even though `.beta` and `.unstable` differ only in `channel`. The tracks
        // split on GitHub's `prerelease` flag, and BetterDisplay resolves its
        // channel from two Settings toggles rather than from the bundle id (see
        // `BetterDisplayChannel`):
        //   * `.stable`   → prerelease: false — e.g. v4.3.6, v4.3.5; since v5.0.5
        //                 that includes 5.x releases as well as 4.x ones (checked
        //                 2026-09-14; History has the tags).
        //   * `.beta`     ("Receive pre-release updates") → prerelease: true —
        //                 v5.0.3, v5.0.2, … Includes the two `arm64_pre` builds
        //                 (v5.0.0/v5.0.1), which are excluded from what we OFFER
        //                 because they are Apple-silicon-only, but are real history
        //                 and belong in the rail.
        //   * `.unstable` ("Receive internal pre-release updates") → deliberately
        //                 the same feed as `.beta`. The internal track has no
        //                 per-version notes anywhere: its items link
        //                 `changelog.html?tag=pre`, and that rolling release's body
        //                 is static boilerplate about what internal builds are. The
        //                 pre track is where those builds come from and the closest
        //                 true history for them; without this third registration the
        //                 channel-aware lookup would fall back to `.stable` and show
        //                 an internal-track user the stable releases' notes instead.
        //
        // That rolling `pre` release cannot leak into either rail as an entry titled
        // "pre": GitHub orders this endpoint by `created_at`, and `pre` was created
        // 2022-04-06, years before the 40th-newest release when checked (2026-08-27
        // and 2026-09-14; History has that release's date). It is far outside a
        // `per_page=40` window and sinks further with every release the vendor cuts.
        //
        // `skipSections` drops the contributor roster. It is not a changelog: about
        // half of the newest 40 releases carried it when checked (2026-08-27 and
        // 2026-09-14; History has the counts), the roster repeated down a 15-row
        // rail. The vendor gives no marker for it (no HTML comment, no `<details>`
        // in the 40 bodies checked), so the heading IS the marker, and they have
        // spelled it two ways. Both are listed. `### Localization Improvements`
        // (v3.3.4) is deliberately NOT listed — that one holds real changes, which
        // is why the match is whole-heading rather than a substring.
        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),

        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .beta,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),

        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .unstable,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),
        ],
        bindingProofs: [
        // BetterDisplay declares its own tag names because its feed spells them
        // `pre`/`internal` and no `ReleaseChannel` case does. Anchored on the tag
        // the resolution actually carries: retype `preTag` and this fails, where
        // `allowedChannels` would silently build a set matching nothing and drop
        // the user to stable.
        //
        // NOT `^pre$`. `sparkleChannelNames` is a Set rendered one element per
        // line, and `.unstable` carries two, so `^`/`$` — which match the whole
        // string in `NSRegularExpression`'s default mode, not each line — would
        // fail on the two-tag resolution depending on Set order. `\b` bounds the
        // token without depending on how many tags sit beside it.
        ChannelProofKey("pro.betterdisplay.BetterDisplay", .beta):
            .recipeAnchor(#"\bpre\b"#, in: ["sparkleChannelNames"]),
        ChannelProofKey("pro.betterdisplay.BetterDisplay", .unstable):
            .recipeAnchor(#"\binternal\b"#, in: ["sparkleChannelNames"]),
        ])

    /// The two spellings BetterDisplay has used for its contributor roster, shared by
    /// its three per-track recipes so a third spelling is added in one place rather
    /// than three. See the recipes' comment for why this is per-app and whole-heading.
    private static let betterDisplayContributorRosters = [
        "Included Localizations",
        "Localizations included in this release",
    ]
}
