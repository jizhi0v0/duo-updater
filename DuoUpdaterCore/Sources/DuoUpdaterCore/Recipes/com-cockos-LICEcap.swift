import Foundation

enum com_cockos_LICEcap {
    static let bundleID = "com.cockos.LICEcap"
    private static let downloadPage = URL(string: "https://www.cockos.com/licecap/")!
    private static let version = #"[0-9]+\.[0-9]+"#
    private static let macLabel = #"\s+for\s+macOS\s*</a>"#
    private static let macLink = #"<a\s+href=""#
    private static let downloadSection = #"(?i)<b>Download</b>(?:\s*<br\s*/?>){2}\s*"#
        + #"(?:<a\s+href="licecap[0-9]+-install\.exe">\s*LICEcap\s+v\#(version)\s+for\s+Windows\s*</a>[^<]*<br\s*/?>\s*)?"#
        + macLink
    // Capture the dotted label's components and require that the same
    // digits form the filename. The probe joins the capture groups with a dot.
    private static let releaseVersion = downloadSection
        + #"(?=licecap[0-9]+\.dmg">\s*LICEcap\s+v([0-9]+)\.([0-9]+)\#(macLabel))licecap\1\2\.dmg""#

    // History: docs/app-audits/com-cockos-LICEcap.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-cockos-LICEcap",
        probes: [
            // Only the current Download section is authoritative. An archived
            // Mac link cannot stand in for a missing or inconsistent current one.
            VendorProbeRecipe(
                bundleID: bundleID,
                url: downloadPage,
                mode: .responseBody,
                versionPattern: releaseVersion,
                downloadURL: downloadPage,
                changelogURL: downloadPage,
                versionIsBuild: true,
                displayVersionPattern: releaseVersion,
                install: VendorInstallSpec(
                    urlSource: .bodyPatternRelative(
                        downloadSection
                            + #"(licecap[0-9]+\.dmg)"\s*>\s*LICEcap\s+v\#(version)\#(macLabel)"#,
                        base: downloadPage),
                    kind: .dmg)),
        ],
        changelogs: [
            // Each macOS release link is followed by its date, file size and
            // one list. Keep the vendor's platform prefixes in shared notes.
            ChangelogRecipe(
                bundleID: bundleID,
                source: downloadPage,
                entryPattern: macLink + #"licecap[0-9]+\.dmg">\s*LICEcap\s+v(?<version>\#(version))"#
                    + macLabel + #"\s*\((?<date>[^()]+)\)\s*\([^()]+\)"#
                    + #"(?:\s*<br\s*/?>)?\s*<ul\b[^>]*>(?<body>.*?)</ul>"#,
                itemPatterns: [#"<li\b[^>]*>\s*(?<item>.*?)(?=</?li\b|\z)"#]),
        ])
}
