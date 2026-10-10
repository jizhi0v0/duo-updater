import Foundation

enum com_runningwithcrayons_Alfred {
    static let set = AppRecipeSet(
        family: "com-runningwithcrayons-Alfred",
        probes: [
        // History: docs/app-audits/com-runningwithcrayons-Alfred.md#历史与实测
        // Alfred, PRE-RELEASE channel — the missing half of the pair below.
        //
        // A user who ticks "Pre-releases" in Alfred's own Update preferences is
        // resolved to `.beta` by `AlfredChannel`, and the channel guard then refuses
        // the stable recipe — correctly, but with nothing left to answer, so the row
        // read "Failed" indefinitely. (The Sparkle path couldn't cover for it: that
        // binding pointed at `alfredapp.com/appcast.xml` and `/prerelease.xml`, both
        // of which now 404 — the unreadable `SparkleError error 0` in the logs.)
        //
        // Same plist shape as stable, different endpoint. The two frequently serve
        // the SAME build (History has an example), so being on beta doesn't by
        // itself mean a newer version is on offer.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/prerelease.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9]+(?:\.[0-9]+)+)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz),
            channel: .beta),

        // Alfred 5 — Sparkle PLIST appcast (not RSS). Alfred has no Info.plist
        // SUFeedURL (the feed is configured in Alfred's own Preferences), so it
        // reaches us here rather than via SparkleAppcastSource — same situation as
        // the Codex and OrbStack recipes (`Recipes/com-openai-codex.swift`,
        // `Recipes/dev-kdrag0n-MacVirt.swift`). The manifest is a single-release plist: the
        // top-level <key>version</key><string> is the latest build (e.g. 5.7.3),
        // unambiguous vs the descending "## Alfred X.Y.Z" history inside
        // changelogdata. One release listed → first match is correct.
        //
        // One-click: `location` points at a tarball holding `Alfred 5.app` at its
        // root (verified 2026-08-08; History has the check). That URL carries the
        // version, so it's read from the same body rather than fixed.
        // Alfred still self-updates on its own; this only means the row can too.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/general.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9][0-9.]*)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz)),
        ],
        changelogs: [
        // History: docs/app-audits/com-runningwithcrayons-Alfred.md#历史与实测
        // Alfred 5 — `alfredapp.com/changelog/`, the page both probes link. Static
        // HTML, newest first:
        //   <h2>Alfred 5.8.1</h2>
        //   <p>Build 2349, Thursday 24th September 2026</p>
        //   <h3>Workflow Improvements and Fixes</h3>   ← only on larger releases
        //   <ul><li>…<ul><li>…</li></ul></li></ul>
        // The version is the h2's number, the same `version` both update plists
        // carry; the build in the paragraph is the plists' `build`, not part of it.
        // The date is the rest of that paragraph, kept verbatim. The version must
        // be followed directly by `</h2>`, which leaves out the "Alfred 5.0 EA3"
        // early-access entries at the bottom; the page names no other pre-release.
        // The pre-release copy uses this recipe too: its plist has served the same
        // version and build as stable whenever it was read, so there is no
        // separate train to keep apart. Nested lists are one line per `<li>`, cut
        // at the next `<li>`/`<ul>` so a parent and its first child stay apart;
        // `<h3>` section names render as headings.
        ChangelogRecipe(
            bundleID: AlfredChannel.bundleID,
            source: URL(string: "https://www.alfredapp.com/changelog/")!,
            entryPattern:
                #"<h2>\s*Alfred\s+(?<version>[0-9]+(?:\.[0-9]+){1,3})\s*</h2>\s*"#
                + #"(?:<p>\s*Build\s+[0-9]+,\s*(?<date>[^<]*)</p>)?"#
                + #"(?<body>.*?)(?=<h2[\s>]|</section>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)(?=<li[\s>]|</li>|<ul[\s>])"#],
            headingPattern: #"<h3[^>]*>(?<heading>[^<]*)</h3>"#),
        ],
        channelProofs: [
        // Alfred serves stable and pre-release from two endpoints that frequently
        // carry the SAME build (History has a dated example), and the
        // tarball name never mentions a channel — only the endpoint can prove it.
        // Endpoint-scoped for the same reason as IntelliJ EAP: this recipe's
        // install `bodyPattern` is byte-identical to the stable Alfred recipe's
        // (same plist shape, different endpoint) and its `versionPattern` differs
        // only in strictness — neither names a channel. So the endpoint is not
        // merely the best evidence, it is the only evidence there is, and the
        // proof says so.
        ChannelProofKey("com.runningwithcrayons.Alfred", .beta):
            .recipeAnchor(#"prerelease\.xml"#, in: ["url"]),
        ])
}
