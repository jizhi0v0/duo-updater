import Foundation

enum com_deepseek_dsh {
    static let set = AppRecipeSet(
        family: "com-deepseek-dsh",
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
        // only. It is also the channel the vendor's own updater config names. A copy on disk still reads as
        // `.stable` — `ReleaseChannel.detect` has no rule for a `-rc.N` version —
        // so the lookup reaches this recipe by the ladder's last step: another
        // recipe for this bundle id would be preferred over it.
        //
        // `includesPromotedStable` because this line graduates in place: an
        // `0.2.1-rc.5` becomes `0.2.1`, so a release GitHub no longer marks
        // `prerelease` is this app's next build rather than another train's.
        //
        // `tagPattern` is both where the version comes from and which releases are
        // this app's. Tags read `dsh-v<version>`, which the decoder's own
        // `stripLeadingV` cannot read (it drops a leading `v`, not a prefix), and
        // the pattern's `rc`/plain alternation keeps the parallel `-alpha.N` train
        // out: `0.2.2-alpha.2` sits above the build the feed serves, and its notes
        // describe a build no desktop install is offered. Plain versions stay
        // accepted because graduation keeps the same numbering.
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
        ])
}
