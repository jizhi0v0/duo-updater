import Foundation

enum app_dataflare_desktop {
    private static let bundleID = "app.dataflare.desktop"
    private static let version = #"[0-9]+(?:\.[0-9]+){2}"#
    private static let releaseNotes = URL(string: "https://github.com/DataflareApp/dataflare/blob/main/CHANGELOG.md")!

    // History: docs/app-audits/app-dataflare-desktop.md#历史与实测
    // The official Tauri response is a flat object. Check its native updater
    // URL, then derive the website's versioned DMG from the resolved version.
    private static let jsonString = #""(?:[^"\\]|\\.)*""#
    private static let field = #"\#(jsonString)\s*:\s*\#(jsonString)\s*,\s*"#
    private static let beforeVersion = #"(?:(?!"version"\s*:)\#(field))*"#
    private static let beforeURL = #"(?:(?!"url"\s*:)\#(field))*"#
    private static let fieldEnd = #""(?=\s*[,}])"#

    static let set = AppRecipeSet(
        family: "app-dataflare-desktop",
        probes: [
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: "https://api.dataflare.app/release/darwin/aarch64/0.0.0")!,
                mode: .responseBody,
                versionPattern: #"\A\s*\{\s*(?=\#(beforeVersion)"version"\s*:\s*"(\#(version))\#(fieldEnd))"#
                    + #"\#(beforeURL)"url"\s*:\s*"https://assets\.dataflare\.app/release/darwin/aarch64/Dataflare\.app\.tar\.gz\#(fieldEnd)"#,
                downloadURL: URL(string: "https://dataflare.app/download"),
                changelogURL: releaseNotes,
                install: VendorInstallSpec(
                    urlSource: .versionTemplate(
                        "https://assets.dataflare.app/release/darwin/aarch64/Dataflare-{version}.dmg"),
                    kind: .dmg),
                hostRequirement: .init(architectures: [.arm64])),
        ],
        changelogs: [
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://raw.githubusercontent.com/DataflareApp/dataflare/main/CHANGELOG.md")!,
                entryPattern:
                    #"(?m)^##[ \t]+v(?<version>\#(version))[ \t]*\r?\n"#
                    + #"(?:[ \t]*\r?\n\*\*Published:\*\*[ \t]+`(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})T[^`\r\n]+`[ \t]*\r?\n)?"#
                    + #"(?<body>.*?)(?=^##[ \t]|\z)"#,
                itemPatterns: [#"(?m)^[ \t]*[-*][ \t]+(?<item>[^\r\n]+)"#],
                markdownSource: true,
                headingPattern: #"(?m)^\*\*(?<heading>[A-Za-z][A-Za-z \t]+)\*\*[ \t]*\r?$"#),
        ])
}
