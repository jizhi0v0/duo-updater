import Foundation

enum com_macromates_TextMate {
    static let set = AppRecipeSet(
        family: "com-macromates-TextMate",
        changelogs: [
        // History: docs/app-audits/com-macromates-TextMate.md#历史与实测
        // TextMate — the vendor's own release notes, the Markdown file the app
        // renders as Help → Release Notes (`Contents/Resources/About/Changes.html`
        // is built from it), read AT THE RELEASE'S TAG:
        //
        //   ## 2021-03-07 (v2.0.20)
        //
        //   * The TextMate::UI ruby bundle support library should now work with ruby 2.x.
        //   * See [all changes since v2.0.19](https://github.com/…/compare/v2.0.19...v2.0.20)
        //
        // Why not the GitHub release bodies: the stable rail never shows a
        // prerelease body, and this vendor ships the substance in prereleases —
        // v2.0.23's body is one line ("Miscellaneous improvements, see changes
        // since v2.0.22"), the fixes it carries are in v2.0.20–v2.0.22, and the
        // stable bodies before v2.0.19 are empty. This file lists every build in
        // one newest-first list, as the app itself shows it.
        //
        // Why the tag and not `master`: `master`'s copy stops at v2.0.22 — the
        // v2.0.23 entry exists only on the tag. `{version}` follows the build
        // being described, and every 2.0 release has its `v<version>` tag; `source`
        // (master) is only the fallback when no version is known.
        //
        // Headings: `## <date> (v<version>)`, the oldest spelling the version as a
        // compare link (`([v2.0-beta.1](…))`), hence the optional `[`. `\n##\s`
        // ends an entry, and does not stop on the `### Other Changes` group
        // headings inside the long 2.0 entry, whose prose paragraphs are dropped —
        // only `* ` bullets become items. `markdownSource` flattens the trailing
        // compare links and the inline code (`` `${var}` ``).
        ChangelogRecipe(
            bundleID: "com.macromates.TextMate",
            source: URL(string: "https://raw.githubusercontent.com/textmate/textmate/master/Applications/TextMate/about/Changes.md")!,
            entryPattern:
                #"(?:^|\n)##\s+(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s+\(\[?v(?<version>[0-9][^\s\])]*)[^\n]*\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n\*\s+(?<item>[^\n]+)"#],
            markdownSource: true,
            maxEntries: 20,
            sourceTemplate: "https://raw.githubusercontent.com/textmate/textmate/v{version}/Applications/TextMate/about/Changes.md"),
        ],
        githubRules: [
        // TextMate 2 — open-source editor (GPL-3.0) by MacroMates. Its own
        // updater (`Frameworks/SoftwareUpdate`) polls
        // `api.textmate.org/releases/<release|beta|nightly>?v=<short>&os=<x.y.z>`;
        // that endpoint answers an old-style plist `{ url; version; revision;
        // signee; signature; }` whose `url` 302s to THIS repo's release asset, and
        // whose `signature` is a DSA signature by the vendor's own key
        // (`org.textmate.duff`) — nothing we can check. So GitHub, which serves the
        // same bytes and carries the notes, is the route; the endpoint adds only an
        // OS bucket (`os` below 10.12 is answered an older 2.0-rc build), and our
        // host floor (macOS 15) is far above every bucket.
        //
        // Tags read `v2.0.23`; the bundle says 2.0.23 in `CFBundleShortVersionString`
        // and a constant `CFBundleVersion` 9800 in every 2.0.x build, so the
        // marketing version is the only comparable one. Two-part `v2.0` is a real
        // stable tag, hence `(?:\.[0-9]+)+`. Anchored so `v2.0-rc.31` (and the old
        // non-prerelease `v2.0-beta.12.4`) are never read as 2.0.
        //
        // Each release carries exactly one asset, `TextMate_<version>.tbz` — a
        // bzip2 tar holding `TextMate.app` (universal in the current releases).
        // `VendorInstaller` renames it `download.tar.gz` and `ArchiveExtractor`
        // runs `/usr/bin/tar -xf`, which detects bzip2 by content. Signed
        // Developer ID MacroMates Ltd. (45TL96F76G), notarized.
        //
        // Prereleases (v2.0.20–v2.0.22, …) share the tag shape and asset name, and
        // the bundle keeps a plain version: nothing local tells them apart. The
        // track is the app's own setting, read by `TextMateChannel`; this rule
        // answers for `release`.
        GitHubReleaseRule(
            bundleID: "com.macromates.TextMate",
            owner: "textmate", repo: "textmate",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^TextMate_[0-9]+(?:\.[0-9]+)+\.tbz$"#,
            installerKind: .tarGz),
        // Beta — Settings ▸ Software Update ▸ beta (`TextMateChannel`). The
        // vendor's `beta` endpoint answers whichever is newer, a prerelease or a
        // stable release, so this rule reads the whole list and takes the newest
        // of either: the same tag, asset and archive as the release rule. A
        // release with no asset (v2.0.13) is walked past.
        GitHubReleaseRule(
            bundleID: "com.macromates.TextMate",
            owner: "textmate", repo: "textmate",
            usePrereleases: true,
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^TextMate_[0-9]+(?:\.[0-9]+)+\.tbz$"#,
            installerKind: .tarGz,
            channel: .beta),
        ],
        githubChannelProofs: [
        // Anchor, not artifact: tags and asset names carry no channel token, and
        // a beta copy is offered a stable release on purpose. What must not drift
        // is the list read; without it this is a second release rule.
        ChannelProofKey("com.macromates.TextMate", .beta):
            .recipeAnchor(#"^true$"#, in: ["usePrereleases"]),
        ])
}
