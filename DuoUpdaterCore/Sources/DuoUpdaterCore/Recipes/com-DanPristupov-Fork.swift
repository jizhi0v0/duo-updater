import Foundation

enum com_DanPristupov_Fork {
    static let set = AppRecipeSet(
        family: "com-DanPristupov-Fork",
        changelogs: [
        // Fork — git-fork.com/releasenotes is a single server-rendered page with all
        // Mac releases. Each version block opens with, e.g.:
        //   <h4 class="header4 release-notes">Fork 2.67</h4>
        //   ...
        //   <h5 class="date">15 May 2026</h5>
        // and contains any number of items wrapped in:
        //   <div class="media-body"><p class="lead">text</p></div>
        // The block ends at the next <h4 class="header4 release-notes"> tag.
        ChangelogRecipe(
            bundleID: "com.DanPristupov.Fork",
            source: URL(string: "https://git-fork.com/releasenotes")!,
            entryPattern:
                #"<h4 class="header4 release-notes">Fork (?<version>[^<]+)</h4>"#
                + #".*?<h5 class="date">(?<date>[^<]+)</h5>"#
                + #"(?<body>.*?)"#
                + #"(?=<h4 class="header4 release-notes">|$)"#,
            itemPatterns: [
                #"<div class="media-body">\s*<p class="lead">\s*(?<item>.*?)\s*</p>"#,
            ]),
        ],
        bindingProofs: [
        // Fork ships two entirely separate feed documents. Note which is which:
        // the BETA train is the unsuffixed `feed.xml` (also the code-signed
        // `SUFeedURL`, and the shipped default), and stable is the one that had to
        // be given a suffix. So the anchor is the absence of that suffix, and it
        // discriminates precisely because `feed-stable.xml` does not contain the
        // literal `feed.xml`.
        ChannelProofKey("com.DanPristupov.Fork", .beta):
            .recipeAnchor(#"/update/feed\.xml"#, in: ["feedOverride"]),
        ])
}
