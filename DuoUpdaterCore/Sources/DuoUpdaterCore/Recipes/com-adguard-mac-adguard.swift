import Foundation

enum com_adguard_mac_adguard {
    static let set = AppRecipeSet(
        family: "com-adguard-mac-adguard",
        changelogs: [
        // History: docs/app-audits/com-adguard-mac-adguard.md#历史与实测
        // AdGuard — detection and one-click are the generic Sparkle path: every
        // build declares its own track's appcast in `SUFeedURL` (release, beta and
        // nightly builds are separate downloads, `AGChannel` in the same plist).
        // No appcast inlines notes; each item carries one
        // `sparkle:releaseNotesLink` to
        // `link.adtidy.org/forward.html?…&channel=<track>`, which redirects to that
        // track's versions page on adguard.com, localized by Accept-Language. So
        // the page is the one the feed resolved for this copy (`feedPagePattern`),
        // and it follows the track with no logic of its own. `source` is the
        // release appcast, read only by `duo verify`.
        //
        //   * One page per track, newest first, one `<div class="feed__item"
        //     id="version-…">` per release. Its header holds `feed__title`
        //     ("AdGuard for Mac 2.20"; the product words are translated, so the
        //     version is the trailing number) and `feed__release` (a translated
        //     "Release date:" label, ASCII or full-width colon, then the date).
        //     The header is matched with `\s*` between its divs, not `.*?`: a
        //     title the version pattern misses then drops that entry instead of
        //     sliding into the next one.
        //   * The version keeps a trailing word and optional number ("2.20 RC 1",
        //     "2.17 beta", "2.16 RC"), which on release and beta pages is the
        //     feed's `shortVersionString`. Nightly titles are the four-part build
        //     ("2.20.0.2625") while the bundle says "2.20 Nightly 9"; nothing
        //     on the page names the nightly number.
        //   * The body is the `feed__version` block up to the next item (or the
        //     page's trailing `<style>`). Text lines are `md__paragraph`,
        //     `md__list-elem` and `md__quote` divs with no div inside them, so
        //     one pattern stops at the first `</div>` and keeps them in document
        //     order. Section titles are `<h1>`–`<h4 class="md__title …">`.
        //   * Screenshots are `<img class="md__img">` alone inside an
        //     `md__paragraph`, which leaves that paragraph empty after stripping.
        ChangelogRecipe(
            bundleID: "com.adguard.mac.adguard",
            source: URL(string: "https://static.adtidy.org/mac/release/adguard-release-appcast.xml")!,
            entryPattern:
                #"<div class="feed__item"[^>]*>\s*<div class="feed__header">\s*"#
                + #"<div class="feed__title">[^<]*?"#
                + #"(?<version>[0-9]+(?:\.[0-9]+)+(?:\s+[A-Za-z]+(?:\s*[0-9]+)?)?)\s*</div>\s*"#
                + #"(?:<div class="feed__release">\s*<div[^>]*>(?:[^<:：]*[:：]\s*)?"#
                + #"(?<date>[^<]*?)\s*</div>\s*</div>\s*)?"#
                + #"</div>\s*<div class="feed__version">"#
                + #"(?<body>.*?)(?=<div class="feed__item"|<style|</body>)"#,
            itemPatterns: [
                #"<div class="md__(?:paragraph|list-elem|quote)"[^>]*>(?<item>.*?)</div>"#,
            ],
            maxEntries: 10,
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)""#,
            headingPattern: #"<h[1-6]\b[^>]*class="md__title[^"]*"[^>]*>(?<heading>.*?)</h[1-6]>"#,
            feedPagePattern:
                #"^https://link\.adtidy\.org/forward\.html\?app=mac&action=update_release_notes"#
                + #"&from=updater&channel=(?:release|beta|nightly)$"#),
        ])
}
