import Foundation

enum com_microsoft_Powerpoint {
    static let set = AppRecipeSet(
        family: "com-microsoft-Powerpoint",
        probes: [
        // Microsoft PowerPoint — Office suite, unified version. The fwlink 302s to
        // a versioned .pkg on the Office CDN. MAU-managed. The pkg filename carries
        // the BUILD (e.g. `16.109.26053122`, = the app's CFBundleVersion), not the
        // shorter marketing CFBundleShortVersionString (e.g. `16.109.3`), so
        // versionIsBuild routes it to the build-vs-build comparison — otherwise the
        // build would read as "newer" than the marketing version forever.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Powerpoint",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/powerpoint")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!),
                kind: .pkg),
            followRedirects: false),
        ],
        changelogs: [
        // PowerPoint's section of the shared Office for Mac release notes. One `<h2>`
        // per release, dated, then `<p><em>Version 16.113.4 (Build 26100421)</em></p>`
        // (older entries omit the word "Build"), then up to three blocks (Feature
        // updates / Resolved issues / Security updates), each with one `<h3>` per
        // app (`id="powerpoint"`, `"powerpoint-4"`, …) followed by a `<ul>`.
        //
        // Entry version is the MARKETING version (`16.113.4`), the scheme of the
        // installed bundle's CFBundleShortVersionString. The probe reports the
        // build (`16.113.26100421`, = CFBundleVersion: the page's major.minor plus
        // its "Build" number); one capture group cannot join two spans, so the
        // entries cannot carry that form.
        //
        // The item pattern takes only `<li>`s in this app's sections and in
        // "Office Suite" ones (items Microsoft lists for every suite app: mostly
        // CVEs in the shared frameworks, which each app bundles its own copy of).
        // The first `<li>` of a list must follow the app's `<h3>` directly; every
        // later one must start exactly where the previous match ended (`\G`) on a
        // `</li>`, so the chain stops at that list's `</ul>` and never runs into
        // another app's section. `\G` needs ICU (NSRegularExpression); it is not
        // available in Python's `re`.
        ChangelogRecipe(
            bundleID: "com.microsoft.Powerpoint",
            source: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            entryPattern:
                #"<h2 id="[^"]*">(?<date>[^<]+)</h2>\s*"#
                + #"<p><em>Version\s+(?<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)\s+\((?:Build\s+)?[0-9]+\)</em></p>"#
                + #"(?<body>.*?)(?=<h2[\s>]|</main>)"#,
            itemPatterns: [
                #"(?:<h3 id="(?:powerpoint|office-suite)(?:-[0-9]+)?">[^<]*</h3>\s*(?:<ul>\s*<li>|<p>)"#
                + #"|\G(?<=</li>)\s*<li>)"#
                + #"(?<item>.*?)(?:</li>|</p>(?=\s*<h[23]))"#
            ],
            maxEntries: 30),
        ])
}
