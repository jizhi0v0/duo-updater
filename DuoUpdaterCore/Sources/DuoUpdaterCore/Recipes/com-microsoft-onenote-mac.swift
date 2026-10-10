import Foundation

enum com_microsoft_onenote_mac {
    static let set = AppRecipeSet(
        family: "com-microsoft-onenote-mac",
        probes: [
        // History: docs/app-audits/com-microsoft-onenote-mac.md#历史与实测
        // Microsoft OneNote — Office suite, unified version. MAU-managed, and read
        // from the MAU manifest rather than the suite fwlink, the same way Outlook
        // is in `Recipes/com-microsoft-Outlook.swift`.
        //
        // It used to use the suite fwlink (linkid=525133), on the reasoning that
        // there is no dedicated OneNote fwlink and the suite reports the same
        // version. That is true for DETECTION and wrong for INSTALL: that link
        // serves the whole-suite package
        // (`Microsoft_365_and_Office_<build>_Installer.pkg`), not OneNote alone
        // (History has its destination list). Someone who has only OneNote
        // installed and clicks Update would have had the entire Office suite put
        // on their machine.
        //
        // `FullUpdaterLocation` in the MAU manifest is a standalone OneNote
        // package that declares exactly one destination,
        // `/Applications/Microsoft OneNote.app`, signed
        // `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.
        //
        // It must be `FullUpdaterLocation` and not `Location`/`Payload`: those are
        // deltas keyed to a specific starting build, and applying one without its
        // baseline installs a broken app.
        VendorProbeRecipe(
            bundleID: "com.microsoft.onenote.mac",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409ONMC2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onenote/digital-note-taking-app")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_OneNote_[0-9.]+_Updater\.pkg)</string>"#),
                kind: .pkg)),
        ],
        changelogs: [
        // OneNote's section of the shared Office for Mac release notes. One `<h2>`
        // per release, dated, then `<p><em>Version 16.113.4 (Build 26100421)</em></p>`
        // (older entries omit the word "Build"), then up to three blocks (Feature
        // updates / Resolved issues / Security updates), each with one `<h3>` per
        // app (`id="onenote"`, `"onenote-4"`, …) followed by a `<ul>`.
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
        //
        // OneNote's own section is almost always the one line "Quality and
        // performance improvements.", so most entries say only that; when one
        // says more, it is nearly always an Office Suite item (security fixes in
        // the shared frameworks, suite-wide features).
        ChangelogRecipe(
            bundleID: "com.microsoft.onenote.mac",
            source: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            entryPattern:
                #"<h2 id="[^"]*">(?<date>[^<]+)</h2>\s*"#
                + #"<p><em>Version\s+(?<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)\s+\((?:Build\s+)?[0-9]+\)</em></p>"#
                + #"(?<body>.*?)(?=<h2[\s>]|</main>)"#,
            itemPatterns: [
                #"(?:<h3 id="(?:onenote|office-suite)(?:-[0-9]+)?">[^<]*</h3>\s*(?:<ul>\s*<li>|<p>)"#
                + #"|\G(?<=</li>)\s*<li>)"#
                + #"(?<item>.*?)(?:</li>|</p>(?=\s*<h[23]))"#
            ],
            maxEntries: 30),
        ])
}
