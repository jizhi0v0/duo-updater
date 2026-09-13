import Foundation

enum com_jetbrains_air {
    static let set = AppRecipeSet(
        family: "com-jetbrains-air",
        changelogs: [
        // Air (JetBrains) — air.dev/changelog is a Vite/React SPA: the HTML is an
        // empty shell and the changelog data is baked into the hashed JS bundle as
        // *compiled JSX* (no clean HTML, no JSON API). Two-stage handles the hash:
        // `source` is the shell, `indexLinkPattern` follows the `<script src=
        // "/assets/index-<hash>.js">` to the current bundle (the hash changes every
        // deploy, so we must follow it, never pin it). The entry/item patterns then
        // run against that JS. Each release is an object literal:
        //   {version:"261.681.18",date:"June 2, 2026",title:"...",
        //    description:"...",[image:qE,]content:i.jsxs(i.Fragment,{children:[...]})}
        // `description` and `image` are optional and vary per entry, so `body`
        // captures everything from after `title` to the next `},{version:"` (or the
        // array close `}][,;]`) rather than anchoring on those fields.
        //
        // The content JSX takes three shapes, so itemPatterns are tried in order:
        //   1. after-link — <li>/<p> whose children array opens with an AIR issue
        //      link (i.jsx("a",…)); we grab the description text that follows it.
        //      This is what the older structured releases (h4 section + <ul>) use,
        //      so it must run BEFORE h4 or those entries degrade to the bare
        //      "Features and improvements:" section labels.
        //   2. h4 — feature releases render each feature as an <h4> heading; that
        //      heading list is the change summary.
        //   3. prose — small fix releases are just <p> paragraphs; capture the
        //      lead string, skipping the boilerplate "Share your feedback" footer
        //      that closes nearly every entry.
        //   4. description — when content is only that footer, the real note lives
        //      in the entry's `description` field (anchored to the body start).
        // Feature <p>/<li> open with a plain string (not a link), so after-link
        // never fires on them; a parse miss anywhere just falls back to embedding
        // the SPA, which renders fine in a WKWebView.
        ChangelogRecipe(
            bundleID: "com.jetbrains.air",
            source: URL(string: "https://air.dev/changelog")!,
            entryPattern:
                #"\{version:"(?<version>[^"]+)",date:"(?<date>[^"]*)",title:"(?<title>(?:\\.|[^"\\])*)","#
                + #"(?<body>.*?)(?=\},\{version:"|\}\][,;])"#,
            itemPatterns: [
                #"children:\[i\.jsx\("a",.*?children:"(?:\\.|[^"\\])*"\}\)," ","(?<item>(?:\\.|[^"\\])+)""#,
                #""h4",\{.*?children:"(?<item>(?:\\.|[^"\\])+)""#,
                #""p",\{[^{}]*?children:\[?"(?!Share your feedback)(?<item>(?:\\.|[^"\\])+)""#,
                #"^description:"(?<item>(?:\\.|[^"\\])+)""#,
            ],
            minItemLength: 4,
            indexLinkPattern: #"src="(?<link>/assets/index-[^"]*\.js)""#),
        ])
}
