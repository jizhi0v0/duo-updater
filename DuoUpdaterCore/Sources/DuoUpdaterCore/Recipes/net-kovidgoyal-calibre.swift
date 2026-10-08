import Foundation

enum net_kovidgoyal_calibre {
    static let set = AppRecipeSet(
        family: "net-kovidgoyal-calibre",
        probes: [
        // Calibre (direct download) — no self-updater and no `SUFeedURL`; the app
        // only checks for a new version and links to the download page. A copy
        // Homebrew installed is answered by `HomebrewCaskSource` ahead of this
        // probe (`SourceStack`), so this reaches the copies installed from the
        // vendor's dmg.
        //
        //   * Version: `calibre-ebook.com/latest-version`, a plain-text body that
        //     is only the stable version (`9.15.0`). It is the app's own fallback:
        //     the app first reads `code.calibre-ebook.com/latest`, whose certificate
        //     comes from calibre's private CA (the app bundles the root; URLSession
        //     rejects it), and reads this URL when that verification fails.
        //     The pattern is the whole body, with a patch of one or two digits:
        //     preview builds are `x.y.1nn` (`download.calibre-ebook.com/preview/`),
        //     so a preview number in this body is a failure, never a stable offer.
        //   * Preview copies are not this recipe's: `installedVersionPattern`
        //     admits only a stable-shaped installed version, so this probe never
        //     answers for a `9.15.101` copy, and never offers it a stable release.
        //   * Install: `download.calibre-ebook.com/<v>/calibre-<v>.dmg`, the
        //     vendor's own host and the cask's URL. Not the GitHub asset the
        //     download page's `/dist/osx` redirects to: GitHub releases are
        //     removed after the next release. The dmg holds only `calibre.app`
        //     (universal, nested helper apps inside the bundle, nothing installed
        //     outside it), Developer ID Team NTY7FVCEKP, notarized.
        //   * macOS floor: the vendor's download page says calibre works on macOS
        //     14.0 and higher, which is the bundle's `LSMinimumSystemVersion`; the
        //     endpoint states nothing, so the floor is pinned here.
        VendorProbeRecipe(
            bundleID: "net.kovidgoyal.calibre",
            url: URL(string: "https://calibre-ebook.com/latest-version")!,
            mode: .responseBody,
            versionPattern: #"\A\s*([0-9]+\.[0-9]+\.[0-9]{1,2})\s*\z"#,
            downloadURL: URL(string: "https://calibre-ebook.com/download_osx"),
            changelogURL: URL(string: "https://calibre-ebook.com/whats-new"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://download.calibre-ebook.com/{version}/calibre-{version}.dmg"),
                kind: .dmg),
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "14.0"),
            installedVersionPattern: #"^[0-9]+\.[0-9]+(?:\.[0-9]{1,2})?$"#),
        ],
        changelogs: [
        // Calibre — calibre-ebook.com/whats-new is one server-rendered page listing
        // every release newest-first (no hydration). Each release is a
        //   <h2 class="release-title">Release: 9.9 [28 May, 2026]</h2>
        //   <h3 class="category">New features</h3><ul class="entries">
        //     <li class="minor"><span class="title">…text…</span>…</li> …
        // Version and date are both in the <h2> title ("Release: <ver> [<date>]").
        // The body spans the whole release (several category sections), bounded by
        // the next release <h2> or the panes-closing triple </div>. itemPatterns
        // target ONLY <span class="title"> — the real changelog (New features + Bug
        // fixes); the bare <li> "news sources" lists carry no span and are dropped
        // as noise. Item text can contain entities (Preferences-&gt;Searching).
        //
        // The category <h3>s render as headings, but only one whose list opens
        // on a <span class="title"> item: the news-source lists contribute no
        // items, so their headings would stand over nothing.
        ChangelogRecipe(
            bundleID: "net.kovidgoyal.calibre",
            source: URL(string: "https://calibre-ebook.com/whats-new")!,
            entryPattern:
                #"<h2 class="release-title">Release:\s*(?<version>[\d.]+)\s*\[(?<date>[^\]]*)\]</h2>"#
                + #"(?<body>.*?)(?=<h2 class="release-title">|</div>\s*</div>\s*</div>)"#,
            itemPatterns: [#"<span class="title">(?<item>.*?)</span>"#],
            headingPattern:
                #"<h3 class="category">(?<heading>[^<]*)</h3>"#
                + #"(?=\s*<ul[^>]*>\s*<li[^>]*>\s*<span class="title">)"#),
        ])
}
