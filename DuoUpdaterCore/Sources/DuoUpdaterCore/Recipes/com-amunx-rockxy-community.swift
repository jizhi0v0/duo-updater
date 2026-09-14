import Foundation

enum com_amunx_rockxy_community {
    static let set = AppRecipeSet(
        family: "com-amunx-rockxy-community",
        changelogs: [
        // History: docs/app-audits/com-amunx-rockxy-community.md#历史与实测
        // Rockxy — GitHub releases, because the appcast holds exactly ONE item.
        //
        // `raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml` is the
        // address the bundle itself declares in `SUFeedURL`, so
        // `SparkleAppcastSource` already answers for detection and needs no recipe.
        // What it cannot do is history: the vendor rewrites that file in place, so
        // it carries the newest release and nothing else. Its `<description>` is
        // real inline HTML, which the
        // pane WOULD render — but as a single entry, and the version rail then has
        // one rung no matter how many builds the user skipped.
        //
        // github.com/RockxyApp/Rockxy carries the same notes plus the history, and
        // the tag is the marketing version verbatim (e.g. `v0.38.2` → `0.38.2` via
        // `stripLeadingV`), which is what `CFBundleShortVersionString` reports.
        //
        // No `skipSections`. Every body opens with a `> **Distribution notice:**`
        // blockquote about the binary EULA, and the strict pass already drops it —
        // it is not a top-level `-`/`*`/`+` bullet. Naming it in `skipSections`
        // would be a no-op anyway, since it sits under no heading of its own.
        //
        // ⚠️ What this costs on the FAILURE path, which is unique to this recipe.
        // `ReleaseNotesPane.fallback` (`App/Sources/WorkbenchWindowView.swift`)
        // reaches for `changelogURL` BEFORE `releaseNotesHTML`, so a fetch that fails
        // (without a token, `api.github.com` allows 60 requests an hour per IP, shared
        // with every other GitHub request DuoUpdater makes) now
        // web-views the tag page where the pane used to render this appcast's
        // inline notes natively. Unlike Waku (appcast notes are unparseable raw
        // markdown) and Shotbase (appcast carries none), Rockxy's appcast has real
        // inline notes to lose. Accepted rather than reordered: for THIS app the
        // fallback URL is a single tag page, so the inline notes would be strictly
        // better — but for a recipe whose `changelogURL` is a full changelog page
        // the current order is the right one, so the fix is not a local swap.
        ChangelogRecipe(
            bundleID: "com.amunx.rockxy.community",
            source: URL(
                string: "https://api.github.com/repos/RockxyApp/Rockxy/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
