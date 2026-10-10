import Foundation

enum com_microsoft_Outlook {
    static let set = AppRecipeSet(
        family: "com-microsoft-Outlook",
        probes: [
        // History: docs/app-audits/com-microsoft-Outlook.md#历史与实测
        // Microsoft Outlook — Office suite, unified version. Uses the Office
        // AutoUpdate XML manifest (same CDN product tree as the fwlinks), an
        // ARRAY of update dicts. MAU-managed.
        //
        // The manifest is a plist, so each dict's keys are ALPHABETICAL and the
        // newest release comes first, which is why every first-match pattern here
        // reads out of the same (first) dict.
        //
        // The manifest's payload keys, and what each points at:
        //
        //   Location / Payload      → `Outlook_<baseline>_to_<new>_Delta.pkg` on
        //                             the delta entries — a PARTIAL payload
        //   BinaryUpdaterLocation   → `…_BinaryDelta.pkg`, a binary patch
        //   FullUpdaterLocation     → `Microsoft_Outlook_<build>_Updater.pkg`, the
        //                             full standalone package (choice customLocation
        //                             /Applications)
        //
        // Only the full updater is installable. Neither delta carries a baseline
        // guard — their `InstallationCheck()` only tests the min OS version — so
        // running one against the wrong installed build would silently lay down a
        // partial Outlook.
        //
        // Manifest host: `res.public.onecdn.static.microsoft/mro1cdnstorage/`, the
        // host Microsoft documents as MAU's hard-coded manifest endpoint
        // (learn.microsoft.com/microsoft-365/enterprise/network-requests-in-office-2016-for-mac).
        // The same path on `officecdn.microsoft.com` still answers 200 with a
        // well-formed manifest, but it stopped advancing at 16.109 — nothing
        // fails, the probe just reports an old build. The `OPIM2019` App ID is
        // still what the live manifest carries; the "2019" is not a product line.
        // `MicrosoftAutoUpdateManifestHostTests` keeps every MAU recipe off the
        // old host.
        //
        // The URL is READ from `FullUpdaterLocation`, not assembled from the
        // version — same call as AweSun's 0.3.13 fix (building the filename from
        // the version broke the moment Oray renamed the file), so a payload CDN
        // move follows automatically. Both patterns take the
        // first match, so both read out of the same first dict — the pkg is the
        // build we report (`duo verify` re-checks that against the live endpoint,
        // and `microsoftOutlookInstallURLMatchesProbedBuild` guards it in CI).
        //
        // The `Microsoft_Outlook_<build>_Updater.pkg` shape is part of the pattern
        // on purpose: key order inside a dict is alphabetical, so BinaryUpdater
        // (B) and the delta `Location` (L) bracket the one key we want, and the
        // filename guard is what makes a delta unmatchable no matter how the
        // manifest is reordered.
        //
        // Version scheme: `Update Version` is the BUILD (e.g. 16.109.26053122), not the
        // marketing string — the pkg's own Distribution declares both (e.g.
        // CFBundleShortVersionString 16.109.3 / CFBundleVersion 16.109.26053122) —
        // hence `versionIsBuild`. Signed `Developer ID Installer: Microsoft
        // Corporation (UBF8T346G9)`, the same Team as the installed app (read from
        // the pkg's xar signature).
        VendorProbeRecipe(
            bundleID: "com.microsoft.Outlook",
            url: URL(string: "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409OPIM2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/outlook/outlook-for-business")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_Outlook_[0-9.]+_Updater\.pkg)</string>"#),
                kind: .pkg)),
        ],
        changelogs: [
        // Outlook's section of the shared Office for Mac release notes. One `<h2>`
        // per release, dated, then `<p><em>Version 16.113.4 (Build 26100421)</em></p>`
        // (older entries omit the word "Build"), then up to three blocks (Feature
        // updates / Resolved issues / Security updates), each with one `<h3>` per
        // app (`id="outlook"`, `"outlook-4"`, …) followed by a `<ul>`.
        //
        // VERSION MISMATCH, ACCEPTED ON PURPOSE. Entries carry the page's
        // "Version" (`16.113.4`) = CFBundleShortVersionString. The probe compares
        // CFBundleVersion (`16.113.26100421`, from the installer filename,
        // `versionIsBuild: true`). The page names one release both ways ("Version
        // 16.113.4 (Build 26100421)"), but one capture group cannot join two
        // spans. So the running-version dot never lights on these entries,
        // `Changelog.carries(version:)` is false for the offered build (the notes
        // never count as confirmed and are re-read), and verify's lag/lead checks
        // don't fire (`Verify.buildDate` reads `16.113` as a date). Matching would
        // need a multi-capture version field, which changes every changelog golden.
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
        // Outlook's section is sometimes a `<p>` with `<br>`-separated lines
        // instead of a list; the `<p>` branch takes that paragraph as one item.
        ChangelogRecipe(
            bundleID: "com.microsoft.Outlook",
            source: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            entryPattern:
                #"<h2 id="[^"]*">(?<date>[^<]+)</h2>\s*"#
                + #"<p><em>Version\s+(?<version>[0-9]+\.[0-9]+(?:\.[0-9]+)?)\s+\((?:Build\s+)?[0-9]+\)</em></p>"#
                + #"(?<body>.*?)(?=<h2[\s>]|</main>)"#,
            itemPatterns: [
                #"(?:<h3 id="(?:outlook|office-suite)(?:-[0-9]+)?">[^<]*</h3>\s*(?:<ul>\s*<li>|<p>)"#
                + #"|\G(?<=</li>)\s*<li>)"#
                + #"(?<item>.*?)(?:</li>|</p>(?=\s*<h[23]))"#
            ],
            maxEntries: 30),
        ])
}
