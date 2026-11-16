import Foundation

enum com_mothersruin_SuspiciousPackageApp {
    // History: docs/app-audits/com-mothersruin-SuspiciousPackageApp.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-mothersruin-SuspiciousPackageApp",
        probes: [
            // The vendor's single-release plist names the application, marketing
            // version, build and minimum macOS. Compare the marketing string;
            // the unrelated build counter is not part of the archive filename.
            // The identity prefix prevents another product's plist from resolving.
            // The versioned full DMG contains only the app and its embedded
            // Quick Look extension / spkg tool; the same-Team install gate applies.
            VendorProbeRecipe(
                bundleID: "com.mothersruin.SuspiciousPackageApp",
                url: URL(string: "https://www.mothersruin.com/software/SuspiciousPackage/data/SuspiciousPackageVersionInfo.plist")!,
                mode: .responseBody,
                versionPattern: #"<key>CFBundleIdentifier</key>\s*<string>com\.mothersruin\.SuspiciousPackageApp</string>\s*<key>CFBundleShortVersionString</key>\s*<string>([0-9]+(?:\.[0-9]+)+)</string>"#,
                downloadURL: URL(string: "https://www.mothersruin.com/software/SuspiciousPackage/get.html")!,
                changelogURL: URL(string: "https://www.mothersruin.com/software/SuspiciousPackage/relnotes.html")!,
                minimumSystemVersionPattern: #"<key>MRSUpdateRequiredOSVersion</key>\s*<string>([0-9]+(?:\.[0-9]+)*)</string>"#,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate("https://www.mothersruin.com/software/archives/SuspiciousPackage-{version}.dmg"),
                    kind: .dmg)),
        ],
        changelogs: [
            // One table row per released version; the bundle build in parentheses
            // is metadata, not part of the displayed version. Nested lists become
            // separate notes so a parent does not swallow its first child.
            // A blockquote after a nested list is its own item; one already
            // inside a plain li stays in that li, including any following text.
            ChangelogRecipe(
                bundleID: "com.mothersruin.SuspiciousPackageApp",
                source: URL(string: "https://www.mothersruin.com/software/SuspiciousPackage/relnotes.html")!,
                entryPattern:
                    #"<tr>\s*<td class="vnum">\s*(?<version>[0-9]+(?:\.[0-9]+)+)\s*<span class="bundle-version">[^<]*</span>\s*</td>\s*<td class="vnotes">\s*<em class="date">Released on (?<date>[^<]+)</em>(?<body>.*?)</td>\s*</tr>"#,
                itemPatterns: [#"<(?:li|blockquote)\b[^>]*>(?<item>.*?)(?=<li\b|</li>|<ul\b|</ul>|\z)"#]),
        ])
}
