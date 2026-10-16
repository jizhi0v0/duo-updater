import Foundation

enum com_cu4uc_mounty {
    static let set = AppRecipeSet(
        family: "com-cu4uc-mounty",
        probes: [
        // History: docs/app-audits/com-cu4uc-mounty.md#历史与实测
        // Mounty for NTFS — a menu-bar GUI over ntfs-3g. No Sparkle, no updater of
        // its own (no URL in the binary): the vendor publishes releases only on
        // its one-page site, mounty.app, whose "Version History" section lists
        // every release newest-first as
        //   <h4>Version 2.4 - 29th of December 2023 - <a href="releases/Mounty-2.4.dmg">download</a></h4>
        // NOTE: HTML scrape — refresh if the page is redesigned.
        //
        // The Homebrew cask `mounty` has no `auto_updates`, so a brew-installed
        // copy is answered by `HomebrewCaskSource` first; this probe serves the
        // copies downloaded from the site.
        //
        // The version is read only from those `<h4>Version <v> - ` headings: the
        // trailing ` -` keeps a `2.5b1` / `2.5 beta` heading from being read as
        // a stable `2.5`. Versions are two-part (`1.10` follows `1.9`), the
        // marketing string, equal to the bundle's `CFBundleShortVersionString`.
        //
        // One-click: `releases/Mounty-<v>.dmg` on the vendor's own host, built
        // from the version this probe resolved, so the version compared is the
        // version downloaded. The dmg holds only `Mounty.app` (universal),
        // Developer ID Team SG6DU88C24, notarized; its only nested app is
        // the `LSBackgroundOnly` login item `MountyHelper`, which launches Mounty
        // and exits. Nothing is installed outside the bundle, so `.dmg` is right.
        // The page publishes no digest. It names the newest release on the only
        // track there is — the same file anyone downloads by hand.
        VendorProbeRecipe(
            bundleID: "com.cu4uc.mounty",
            url: URL(string: "https://mounty.app/")!,
            mode: .responseBody,
            versionPattern: #"<h4>\s*Version\s+([0-9]+(?:\.[0-9]+)+)\s+-"#,
            downloadURL: URL(string: "https://mounty.app/#installation"),
            changelogURL: URL(string: "https://mounty.app/#versions"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate("https://mounty.app/releases/Mounty-{version}.dmg"),
                kind: .dmg)),
        ],
        changelogs: [
        // The same page's "Version History": per release an `<h4>` with version
        // and date, then a `<ul>` of `<li>` items (1.1, the first release, has
        // `<p>` paragraphs instead). The body runs to the next `<h4>` or the
        // section's closing `</div>`, so the Disqus block after it never becomes
        // an item. No headings inside a release.
        ChangelogRecipe(
            bundleID: "com.cu4uc.mounty",
            source: URL(string: "https://mounty.app/")!,
            entryPattern:
                #"<h4>\s*Version\s+(?<version>[0-9]+(?:\.[0-9]+)+)\s+-\s+(?<date>[^<]*?)\s+-\s+"#
                + #"<a\b[^>]*>[^<]*</a>\s*</h4>(?<body>.*?)(?=<h4\b|</div>)"#,
            itemPatterns: [#"<(li|p)\b[^>]*>(?<item>.*?)</\1>"#],
            maxEntries: 25),
        ])
}
