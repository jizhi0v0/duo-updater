import Foundation

enum com_readdle_PDFExpert_Mac {
    static let set = AppRecipeSet(
        family: "com-readdle-PDFExpert-Mac",
        changelogs: [
        // PDF Expert — the appcast's `sparkle:releaseNotesLink` is
        // `pem3/changelog.html`, a 3.5 KB page holding ONLY the newest release's
        // paragraph, so the pane could show one version and no history. The
        // vendor's multi-version page is the `sparkle:fullReleaseNotesLink` beside
        // it (`pem3/changelog`) — a link element `SparkleAppcastParser` does not
        // read at all, which is why this is a recipe and not a feed field.
        //
        // Server-rendered and unusually plain: the whole document uses four tags
        // (`p`, `strong`, `br`, `body`) and carries no links, no images and no
        // dates — so there is no `date` group to capture, and one item pattern
        // covers every entry. Each release is
        //   <p><strong>Version 3.13.2 </strong></p> text<br />more text<br />
        // with the trailing space present on some headings and not others.
        //
        // 88 headings, 85 distinct versions: `3.10.23`, `3.10.22` and `3.9.2` each
        // appear TWICE, and for two of those the two bodies are different text
        // (3.10.23 is "Meet Draw on Mac…" in one and "Hello from the team!…" in
        // the other). `ChangelogExtractor` dedupes on version + title and the
        // title is nil here, so the second body of each pair is dropped silently.
        // Left as is rather than worked around: which of two same-numbered
        // paragraphs is the real one is the vendor's question, not a regex's, and
        // both fall outside the `maxEntries` window anyway except 3.10.2x.
        //
        // `body` runs to the next heading or `</body>`, and items are the runs of
        // text between the `<br />`s — `[^<]+` cannot cross a tag, so the split is
        // the markup's own. The `(?:^|>)` prefix is why the run starts where the
        // text does: without it the engine simply resumes one character past the
        // `<` it stopped on and every item after the first reads "br />…".
        // `\s*(?:-\s+)?` then drops the leading dash the pre-3.1 entries spell
        // their bullets with ("- Stability and performance improvements") — the
        // `\s*` is load-bearing there, since a run opens on the newline after
        // `<br />` and the dash is not at the match start until that is consumed.
        // Empty runs (the `<br /><br />` pairs the older entries pad paragraphs
        // with) clean to "" and are dropped by the default `minItemLength` of 1;
        // no larger floor is set, because across all 88 entries of the live page
        // there is not one cleaned item shorter than four characters, so a floor
        // would be a knob no input measures and a trap for the first short note.
        //
        // ⚠️ The heading is matched as `<p[^>]*>`, not a bare `<p>`, and that is
        // the one piece of slack worth spending here: this recipe's failure mode
        // is NOT the usual zero entries. If the terminator stops matching, the
        // first block simply runs to `</body>` and the result is ONE entry,
        // correctly versioned `3.13.2`, carrying every paragraph on the page —
        // and `duo verify` records only the newest version, never an entry count,
        // so that failure sweeps green. A single added class or attribute on the
        // vendor's `<p>` would have been enough.
        ChangelogRecipe(
            bundleID: "com.readdle.pdfexpert-mac",
            source: URL(string: "https://pdfexpert.com/pem3/changelog")!,
            entryPattern:
                #"<strong>\s*Version\s+(?<version>[0-9][0-9.]*)\s*</strong>\s*</p>"#
                + #"(?<body>.*?)(?=<p[^>]*>\s*<strong>\s*Version\s|</body>)"#,
            itemPatterns: [#"(?:^|>)\s*(?:-\s+)?(?<item>[^<]+)"#],
            maxEntries: 20),
        ],
        supersededFeeds: [
        // PDF Expert (Readdle). Its `SUFeedURL` points at `/release/appcast.xml`,
        // which the vendor froze on 2022-07-12: four items, newest build 764
        // (2.5.22, July 2022). Three of them cap out at `maximumSystemVersion`
        // 10.10–10.12, but the fourth does NOT, so on a current Mac the generic
        // source resolves that feed, picks 2.5.22 as "latest", finds it older than
        // the installed 3.13.2 and reports the app up to date — forever, with no
        // error anywhere. Nothing else picks the app up either: the `pdf-expert`
        // cask is `auto_updates: true`, which `HomebrewCaskSource` skips by design.
        // The live feed is `/pem3/release/appcast.xml`.
        //
        // Why this address and not merely a newer-looking one. The pem3 item for
        // build 1172 links a zip whose `.app` is Developer ID-signed by Team
        // 3L68KQB4HG and notarized (`spctl` accepts it) — Apple's attestation that
        // Readdle produced it, which no operator of that CDN path could forge — and
        // Homebrew's `pdf-expert` cask, maintained by nobody here, points at the
        // same tree and the same build. The zip's own `SUPublicEDKey`
        // (`K5sdt9UTWp/TcP48oRVycKUqWUbi0Tp37zrWtFYCCfw=`) does verify that item's
        // `sparkle:edSignature` over the exact 128 MB payload (Ed25519, checked
        // 2026-09-04), but note what that is and is not: the key and the payload
        // both come from the pem3 tree, so it proves the feed is internally
        // consistent, NOT that this key is the one the app in front of a user
        // holds. It cannot be made independent — 764, 936 and 964, the builds the
        // DEAD feed serves, carry no `SUPublicEDKey` at all (range-read from their
        // zips, 2026-09-04), and all four builds declare the same dead address.
        // The signature that actually gates the install for a stuck user is
        // therefore the Developer ID / Team check, not EdDSA (see
        // `UpdatePolicy`'s unsigned-feed branch).
        "com.readdle.pdfexpert-mac": SparkleFeedCatalog.SupersededFeed(
            declared: URL(string: "https://downloads.pdfexpert.com/release/appcast.xml")!,
            live: URL(string: "https://downloads.pdfexpert.com/pem3/release/appcast.xml")!),
        ])
}
