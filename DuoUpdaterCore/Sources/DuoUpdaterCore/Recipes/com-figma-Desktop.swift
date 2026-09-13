import Foundation

enum com_figma_Desktop {
    static let set = AppRecipeSet(
        family: "com-figma-Desktop",
        probes: [
        // Figma desktop (stable) — official per-arch "latest" manifest (the same
        // RELEASE.json the Homebrew cask livecheck reads). `version` is first and
        // matches the app's CFBundleShortVersionString (e.g. 126.4.13). mac-arm is
        // the Apple-silicon flavor; an Intel build would use the `mac` path. The
        // body also carries the absolute zip URL ("url":"…/Figma-<ver>.zip") — the
        // install spec captures that for one-click. Confirmed 2026-06-06: the
        // downloaded Figma-126.4.13.zip is a notarized Developer ID build, Team
        // T8RA8NE3B7 (Figma, Inc.), bundle id com.figma.Desktop == the installed
        // app, so the VendorInstaller Team gate passes. ChangelogRecipe renders the
        // notes. (Figma also self-updates via Squirrel; this is a manual fallback.)
        VendorProbeRecipe(
            bundleID: "com.figma.Desktop",
            url: URL(string: "https://desktop.figma.com/mac-arm/RELEASE.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.figma.com/downloads/"),
            changelogURL: URL(string: "https://www.figma.com/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://desktop\.figma\.com/[^"]+\.zip)""#),
                kind: .zip)),

        // Figma Beta — a SEPARATE app (NOT an in-app toggle): its own bundle id
        // com.figma.DesktopBeta, its own "Figma Beta.app", and a parallel endpoint
        // tree under /beta/. Pattern A (independent installs), so no cross-channel
        // risk — this recipe only ever resolves against a real Figma Beta install,
        // which detects as `.beta` (verified via channel-verify on the 126.6.2
        // bundle). Endpoint mirrors stable exactly: RELEASE.json → version + the
        // FigmaBeta-<ver>.zip url. Same signer as stable (Team T8RA8NE3B7,
        // confirmed 2026-06-06 on the real FigmaBeta-126.6.2.zip), so one-click is
        // safe behind the same Team gate. Notes share the product release-notes page
        // (Figma publishes no separate beta changelog).
        VendorProbeRecipe(
            bundleID: "com.figma.DesktopBeta",
            url: URL(string: "https://desktop.figma.com/mac-arm/beta/RELEASE.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.figma.com/downloads/"),
            changelogURL: URL(string: "https://www.figma.com/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"(https://desktop\.figma\.com/[^"]+\.zip)""#),
                kind: .zip),
            channel: .beta),
        ],
        changelogs: [
        // Figma (desktop) — read the vendor's own Atom feed rather than the HTML
        // page: `https://www.figma.com/release-notes/feed/atom.xml`. The `Content-Type`
        // header on that response reads `application/rss+xml`, but the body is a
        // standard Atom document (`<feed xmlns="http://www.w3.org/2005/Atom">`) —
        // don't trust the header, trust the markup. Switched away from the page
        // (which the entryPattern below used to scrape) because the page's markup is
        // a client-hydrated shell with CSS classes hashed per deploy — the same
        // fragility class as every other "scrape the rendered page" recipe in this
        // file — while the feed's element names (`entry`/`title`/`updated`/`content`)
        // are a published, stable contract. It also fixes a real bug in the old
        // recipe: the page lazy-loads posts as you scroll, so the live DOM only ever
        // had ~8 `<article>` blocks to match against however large `maxEntries` was
        // set — the feed carries hundreds, so the existing `maxEntries: 20` cap now
        // actually engages.
        //
        // Each entry (captured verbatim 2026-08-19):
        //   <entry>
        //       <title type="html"><![CDATA[Recommend resources you want users to discover and use]]></title>
        //       <id>dece0d00-5f03-4a5d-aa04-3b0fad21b5eb</id>
        //       <link href="https://www.figma.com/release-notes/?title=…"/>
        //       <updated>2026-08-17T00:00:00.000Z</updated>
        //       <content type="html"><![CDATA[Admins can now choose which resources…]]></content>
        //   </entry>
        // This is still Figma's *product* release-notes feed (Figma Design / Make /
        // FigJam announcements), NOT desktop-app build notes — there is no per-entry
        // app version. The desktop build version lives only at
        // desktop.figma.com/mac/RELEASE.json with no human notes, so this remains the
        // best changelog surface, and the post title still fills `version` / the post
        // date still fills `date` — same mapping as the old page recipe, just read
        // from a sturdier document.
        //
        // Both `title` and `content` are `<![CDATA[…]]>`-wrapped. A naive `<[^>]*>`
        // tag-stripper applied BEFORE the CDATA payload is pulled out will eat the
        // whole `<![CDATA[…]]>` construct, because `[^>]*` happily reads through to
        // the `>` that closes `]]>` — so the capture groups below land strictly
        // *inside* the CDATA delimiters (`<!\[CDATA\[(?<…>.*?)\]\]>`), and the
        // generic stripTags/decodeEntities cleanup only ever runs on text already
        // isolated that way. Checked against the live feed (444 entries, 2026-08-19):
        // no entry's title or content carries embedded HTML tags today, so that
        // cleanup is currently a no-op — but the ordering is still correct for the
        // day one does.
        //
        // `date` truncates the ISO timestamp to just its date portion (`[^T]+` before
        // the literal `T`) — the same convention already used for the GitHub-releases
        // recipes (Ollama, RustDesk) reading `<relative-time datetime="…">`, and the
        // prevailing `YYYY-MM-DD` shape most recipes in `ChangelogRecipeRegistry` use.
        //
        // Trade-off (accepted, not a regression): `content` is a one-sentence
        // summary, not the fuller multi-paragraph prose the HTML page rendered for
        // its top posts. Verified against the same 8 posts on 2026-08-19: combined
        // item text drops from 3390 to 1062 characters (31%) versus the old
        // `<article>`/`<p>` scrape, while every title and date matches byte-for-byte.
        // Chosen deliberately for stability over completeness.
        ChangelogRecipe(
            bundleID: "com.figma.Desktop",
            source: URL(string: "https://www.figma.com/release-notes/feed/atom.xml")!,
            entryPattern:
                #"<entry>\s*"#
                + #"<title type="html"><!\[CDATA\[(?<version>.*?)\]\]></title>\s*"#
                + #"<id>[^<]*</id>\s*"#
                + #"<link[^>]*/>\s*"#
                + #"<updated>(?<date>[^T]+)T[^<]*</updated>\s*"#
                + #"(?<body><content type="html"><!\[CDATA\[.*?\]\]></content>)"#,
            itemPatterns: [#"<content type="html"><!\[CDATA\[(?<item>.*?)\]\]></content>"#],
            maxEntries: 20),
        ],
        channelProofs: [
        ChannelProofKey("com.figma.DesktopBeta", .beta): .artifact(#"/beta/FigmaBeta-"#),
        ])
}
