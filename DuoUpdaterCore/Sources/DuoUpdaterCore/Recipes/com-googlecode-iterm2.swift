import Foundation

enum com_googlecode_iterm2 {
    static let set = AppRecipeSet(
        family: "com-googlecode-iterm2",
        changelogs: [
        // History: docs/app-audits/com-googlecode-iterm2.md#历史与实测
        // iTerm2 — none of its three appcasts inlines notes; every item links one
        // plain-text file per track instead: `full_changes.txt` (stable,
        // `final_modern.xml`), `testing_changes3.txt` (test release,
        // `testing_modern.xml`) and `nightly_changes.txt` (nightly). So the page is
        // whatever the feed resolved for this copy (`feedPagePattern`); `source` is
        // the stable appcast, read only by `duo verify` to resolve a page of its own.
        //
        // The pattern admits the stable and test-release files and nothing else.
        // `nightly_changes.txt` is a commit log (dated subjects and prose bodies,
        // no version line), so a nightly copy is not offered this recipe and its
        // pane embeds that file as before — and because the page comes from the
        // copy's own feed, a nightly copy can never be handed the stable file, nor
        // a stable copy the nightly one.
        //
        // Each file is one release:
        //
        //   Version 3.7.3 of iTerm2 was built on September 22, 2026.
        //
        //   Bug Fixes:
        //   - Fixed the Python API not reporting OSC 8
        //     hyperlinks. A cell’s CellStyle.url is now
        //
        // The date may wrap onto the next line (`\s+`), and `of iTerm2` is not
        // always there. Items are hard-wrapped with a two-space indent; the item
        // pattern takes the `- ` line plus every indented line after it, and
        // whitespace collapsing joins them into one line. `[^\n]`, not `.`: every
        // pattern is compiled with dot-matches-newline. Section labels
        // (`Bug Fixes:`, `New Features:`, …) are unindented and end in a colon,
        // and are kept as headings. Unindented prose that is neither (the test
        // release's opening credit line) is not an item and is dropped. Tags and
        // entities are left alone: this is plain text, and it writes menu paths
        // as `Settings > Profiles`.
        ChangelogRecipe(
            bundleID: "com.googlecode.iterm2",
            source: URL(string: "https://iterm2.com/appcasts/final_modern.xml")!,
            entryPattern:
                #"(?m)^Version[ \t]+(?<version>\d+(?:\.\d+)+[0-9a-z-]*)\s+(?:of\s+iTerm2\s+)?"#
                + #"was\s+built\s+on\s+(?<date>[a-z]+\s+\d{1,2},\s+\d{4})\.[ \t]*\n"#
                + #"(?<body>.*?)(?=\nVersion[ \t]+\d|\z)"#,
            itemPatterns: [#"(?m)^-[ \t]+(?<item>[^\n]*(?:\n[ \t]+\S[^\n]*)*)"#],
            stripTags: false,
            decodeEntities: false,
            maxEntries: 1,
            headingPattern: #"(?m)^(?<heading>[a-z][a-z ]*[a-z]):[ \t]*$"#,
            feedPagePattern:
                #"^https://iterm2\.com/appcasts/(?:full_changes|testing_changes3)\.txt$"#),
        ],
        bindingProofs: [
        // iTerm2's test-release toggle is a feed swap: stable and testing share
        // host and path prefix and differ only in the filename the bundle
        // declares under `SUFeedURLForTesting`, which is what the anchor targets.
        ChannelProofKey("com.googlecode.iterm2", .beta):
            .recipeAnchor(#"testing_modern\.xml"#, in: ["feedOverride"]),
        ])
}
