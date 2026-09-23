import Foundation

enum org_videolan_vlc {
    static let set = AppRecipeSet(
        family: "org-videolan-vlc",
        probes: [
        // History: docs/app-audits/org-videolan-vlc.md#历史与实测
        // VLC — official Sparkle appcast. Lists releases ascending, so
        // highestVersion (not first) picks the current one.
        //
        // If a nightly-channel variant of this recipe is ever added: no `install:`
        // — nightly is ad-hoc signed, no Team ID (docs/app-audits/org-videolan-vlc.md, #95).
        VendorProbeRecipe(
            bundleID: "org.videolan.vlc",
            url: URL(string: "https://update.videolan.org/vlc/sparkle/vlc-arm64.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9.]+)""#,
            changelogURL: URL(string: "https://www.videolan.org/vlc/releases/"),
            selectHighest: true,
            // Ascending appcast → take the LAST enclosure (newest). http mirror
            // gateway is upgraded to https by the source. Team 75GAHG3SZQ.
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(#"url="(https?://get\.videolan\.org/vlc/[^"]+arm64\.dmg)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // VLC — two-stage. `source` is the newest-first releases index; the
        // `indexLinkPattern` follows its first per-version link (e.g.
        // /vlc/releases/3.0.23.html) to the detail page, which avoids version-pinning
        // *and* the merge trap: VLC folds 3.0.19/3.0.20 — and 3.0.22/3.0.23 — onto a
        // single page, so the page is not always named after the latest version;
        // following the real href is correct where templating a version would 404.
        // (The companion NEWS file at code.videolan.org is behind an Anubis
        // proof-of-work wall, so it can't be fetched — hence the marketing page.)
        // The detail page is mostly marketing, but the per-release section carries
        // the real changelog. Its heading is "<version> Fixes" on 3.0.18–3.0.23
        // pages and "<version> Highlights" from 3.0.24 on; the Fixes form may read
        // "3.0.22/3.0.23 Fixes" (the slash form lists the superseded build), so
        // `(?:[\d.]+/)*` skips the leading versions and captures the final one. The
        // version must have at least three parts, so the generic "3.0 Highlights"
        // marketing heading is never read as a release. The release block shares a
        // single <section> with the "3.0 Highlights" / "3.0 Features" marketing
        // lists, so the body lookahead must stop at the next <h1> — bounding to
        // </section> would swallow those feature bullets. No per-entry date is printed.
        ChangelogRecipe(
            bundleID: "org.videolan.vlc",
            source: URL(string: "https://www.videolan.org/vlc/releases/")!,
            entryPattern:
                #"<h1[^>]*>(?:[\d.]+/)*(?<version>\d+(?:\.\d+){2,})\s*(?:Fixes|Highlights)</h1>\s*"#
                + #"(?<body>.*?)(?=<h1|</section>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 1,
            indexLinkPattern: #"href="(?<link>/vlc/releases/\d[^"]*\.html)""#),
        ])
}
