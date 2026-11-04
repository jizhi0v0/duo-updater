import Foundation

enum com_deepseek_dsh {
    static let set = AppRecipeSet(
        family: "com-deepseek-dsh",
        probes: [
        // History: docs/app-audits/com-deepseek-dsh.md#历史与实测
        // DeepSeek Harness — the `-alpha.N` train, which the vendor's own updater
        // cannot reach. This recipe answers ONLY for a copy whose version says
        // `-alpha.N` (`ReleaseChannel.detect`'s scoped 0.999 rule); every stable
        // and `-rc.N` copy keeps reading `.stable` and keeps being answered by the
        // Electron feed below, so the two tracks never cross.
        //
        // Why a probe at all: an alpha build's `app-update.yml` names the SAME
        // generic feed as a stable one (`channel: nightly`, read off the real
        // 2026-11-03 `0.2.2-alpha.3` DMG). That feed serves the `-rc.N` line
        // (`nightly-mac.yml` was `0.2.1-rc.5` on 2026-11-03, older than the
        // installed alpha), and every alpha-shaped manifest name is 404
        // (`alpha-mac.yml`, `beta-`, `canary-`, `latest-`, plus three other path
        // shapes, re-probed the same day). So the app never offers an alpha to
        // anyone; the vendor hands the next one out as a DMG at a versioned path,
        // and that DMG is the only way an alpha install moves forward.
        //
        // Version surface: the repo's releases ATOM feed, not the REST API the
        // changelog recipe reads. The atom feed is the same vendor data (newest
        // first, 10 entries, full bodies) with no token and no API budget — a
        // probe runs on every check, and spending the shared GitHub budget to
        // learn one version would rate-limit every GitHub-rule app on the machine.
        //
        // `selectHighest` rather than "first entry wins": the feed is ordered by
        // publish time, and the vendor has already published a lower-numbered
        // build (`0.2.1-rc.5`, 2026-10-30) after a higher one (`0.2.2-alpha.2`,
        // 2026-10-28). The version compared has to be the newest by number.
        //
        // No `entryStartPattern` beside it: the pattern is pinned to the feed's
        // own `<title>` element, so the only strings it can match are release
        // titles — the body's compare links (`dsh-v0.2.2-alpha.2...dsh-v0.2.2-alpha.3`)
        // are HTML-escaped and carry no `<title>`. Slicing would buy nothing, and
        // `versionTemplate` already makes the compared version and the downloaded
        // one the same string, which is the drift `entryStartPattern` exists to
        // prevent.
        //
        // The version set is the whole train — `-alpha.N`, `-rc.N` and plain —
        // because the vendor graduates in place (`0.2.2-alpha.3` → `0.2.2-rc.N`
        // → `0.2.2`, same as `0.2.1-rc.5` → `0.2.1`). An `.alpha`-only pattern
        // would stall an alpha install the day its train graduates: the probe
        // would keep resolving the last alpha forever and the feed behind it is
        // shadowed. `VersionComparator` orders the three shapes correctly
        // (`alpha` and `rc` are text runs, a bare release's missing component
        // wins the tie), so the graduating build is simply the newer version.
        //
        // One-click: `<feed base>/bin/mac-arm64/deepseek-harness-<version>-mac-arm64.dmg`
        // — the vendor's own path, filled with the version this probe RESOLVED
        // (`.versionTemplate`, so the version compared is the version downloaded).
        // The bytes there are the vendor's own signed build of the same version
        // the probe reports, notarized under the Team already on disk
        // (`NAN929V4UM`), so VendorInstaller's signature gate holds it to that
        // signer. Which versions the vendor actually publishes as DMGs is
        // measured in the family's History.
        //
        // The vendor does NOT publish a DMG for every alpha tag it writes
        // (`0.2.2-alpha.2` and `0.2.1-alpha.5` never had one — History), so a
        // version read from the feed is not evidence of a download. Hence
        // `selectsHighestPublishedBuild`: the probe HEADs the highest candidate,
        // then the next two, and offers the highest that answers. If none answers
        // it keeps the version, drops one-click and raises
        // `installURLNotFound` — a row with no Update button is a bug report
        // about a missing button; a row whose Update button 404s is a bug report
        // about us. `duo verify` keeps HEADing the resolved URL as well, so a
        // vendor that stops publishing entirely still surfaces there.
        //
        // No `.downloadURL`/`.changelogURL`: the notes come from the `.alpha`
        // `ChangelogRecipe` below, and the atom entry has no human page worth
        // linking that the changelog source does not already name.
        VendorProbeRecipe(
            bundleID: "com.deepseek.dsh",
            url: URL(string: "https://github.com/deepseek-ai/deepseek-harness/releases.atom")!,
            mode: .responseBody,
            versionPattern: #"<title>v([0-9]+(?:\.[0-9]+)+(?:-(?:alpha|rc)\.[0-9]+)?)</title>"#,
            selectHighest: true,
            // The feed names builds the vendor has not packed (History), so the
            // version it resolves must be confirmed against the artifact before it
            // is offered — and the walk goes DOWN rather than failing, because a
            // lower published build is the honest offer for a copy that is behind.
            selectsHighestPublishedBuild: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-{version}-mac-arm64.dmg"),
                kind: .dmg),
            channel: .alpha),
        ],
        changelogs: [
        // History: docs/app-audits/com-deepseek-dsh.md#历史与实测
        // DeepSeek Harness (official) — the notes are the upstream repo's GitHub
        // release bodies; the update feed carries none.
        //
        // Detection and the one-click zip are `ElectronManifestSource`'s: the
        // bundle's own `app-update.yml` names a generic feed on
        // download.deepseek.com with `channel: nightly`, and that manifest has no
        // `releaseNotes`. The desktop app is built from
        // `deepseek-ai/deepseek-harness`, whose Releases carry the notes the
        // vendor wrote — Chinese first, English after — one release per build.
        //
        // `channel: .nightly` is what lets a prerelease through: the desktop line
        // ships `-rc.N` builds, which GitHub marks `prerelease`, and
        // `.gitHubReleases` reads a stable install's notes from non-prereleases
        // only. It is also the channel the vendor's own updater config names. A
        // stable or `-rc.N` copy on disk still reads as `.stable` —
        // `ReleaseChannel.detect` has no rule for a `-rc.N` version — so the
        // lookup reaches this recipe by the ladder's last step, which also means
        // it must stay FIRST in this array: the `.alpha` recipe below is only
        // reachable by an exact channel match, and declaration order is what a
        // `.stable` copy falls back to.
        //
        // `includesPromotedStable` because this line graduates in place: an
        // `0.2.1-rc.5` becomes `0.2.1`, so a release GitHub no longer marks
        // `prerelease` is this app's next build rather than another train's.
        //
        // `tagPattern` is both where the version comes from and which releases are
        // this app's. Tags read `dsh-v<version>`, which the decoder's own
        // `stripLeadingV` cannot read (it drops a leading `v`, not a prefix), and
        // the pattern's `rc`/plain alternation keeps the `-alpha.N` train out:
        // those notes belong to the alpha recipe below, which is the only recipe
        // an alpha install can reach. Plain versions stay accepted because
        // graduation keeps the same numbering.
        //
        // Both languages reach the pane. Each body is Chinese then English under
        // its own headings — raw `<h3>` in recent builds, `###` in earlier ones —
        // so a change appears once per language. The vendor publishes no
        // per-language body, and `GitHubMarkdownParser.firstLanguage` only cuts at
        // a `<!-- lang:xx -->` marker, which these bodies do not carry.
        ChangelogRecipe(
            bundleID: "com.deepseek.dsh",
            source: URL(string: "https://api.github.com/repos/deepseek-ai/deepseek-harness/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .nightly,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^dsh-v([0-9]+(?:\.[0-9]+)+(?:-rc\.[0-9]+)?)$"#),
        // The alpha train's notes — the same upstream bodies, and the recipe an
        // alpha install reaches. The two trains share the bundle id, so the only
        // separation is `channel`, matched exactly by
        // `ChangelogRecipeRegistry.recipe(forBundleID:channel:version:)`; a copy
        // this recipe does not answer for reads `.stable` and lands on the recipe
        // above through the fallback steps.
        //
        // `tagPattern` spans the whole train — `-alpha.N`, `-rc.N` and plain —
        // because the vendor graduates in place (`0.2.2-alpha.N` → `0.2.2-rc.N`
        // → `0.2.2`). An alpha-only pattern would freeze an alpha install's pane
        // on the last alpha the day its train graduates. The entries are
        // deliberately a superset of the recipe above's: these are the builds an
        // alpha copy is moving towards, and the probe beside this file is what
        // makes the graduating one an offered update.
        ChangelogRecipe(
            bundleID: "com.deepseek.dsh",
            source: URL(string: "https://api.github.com/repos/deepseek-ai/deepseek-harness/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .alpha,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^dsh-v([0-9]+(?:\.[0-9]+)+(?:-(?:alpha|rc)\.[0-9]+)?)$"#),
        ],
        // Why this is a `.recipeAnchor` and not an `.artifact` one: the artifact
        // URL deliberately spans the whole train (an alpha copy is offered
        // `-rc.N`/plain builds once the train graduates), so an artifact-side
        // token would have to accept exactly those shapes and would then accept a
        // STABLE build too — a proof that cannot fail. What actually ties this
        // recipe to the channel is upstream of the artifact: the version surface is
        // this repo's own releases feed and the artifact is the vendor's own
        // `deepseek-harness…` path, both of which the anchor pins, while the
        // channel gate keeps the recipe away from stable/`-rc.N` installs.
        channelProofs: [
        ChannelProofKey("com.deepseek.dsh", .alpha):
            .recipeAnchor(#"deepseek-harness"#, in: ["url", "install"]),
        ])
}
