import Foundation

enum com_microsoft_OneDrive {
    static let set = AppRecipeSet(
        family: "com-microsoft-OneDrive",
        probes: [
        // Microsoft OneDrive — Microsoft's "latest" download fwlink. A single 302
        // lands on a versioned .pkg URL on oneclient.sfx.ms. The version is a
        // 4-component path segment (e.g. `26.078.0426.0002`), not a filename, so
        // followRedirects:false reads the Location header instead of lastPathComponent.
        //
        // Capture only the FIRST THREE components: the installed bundle's
        // CFBundleShortVersionString is exactly those (e.g. `26.078.0426`), while the
        // 4th path component is a build revision that the marketing version omits —
        // and CFBundleVersion uses a *different* scheme (e.g. `26078.0426.0002`, first
        // two merged), so neither installed field matches the full 4-component path.
        // Comparing the full path version would read the trailing `.0002` as newer
        // than `26.078.0426` and phantom-update forever. (Verified against a real
        // install: short `26.078.0426`, build `26078.0426.0002`.) A genuine release
        // bumps one of the first three, so first-3 detection stays correct; the only
        // blind spot is a pure 4th-component re-spin under an unchanged marketing
        // version — the safe direction (a missed check, never a phantom), and
        // OneDrive self-updates via OneDriveStandaloneUpdaterDaemon anyway.
        // Install follows the same fwlink.
        VendorProbeRecipe(
            bundleID: "com.microsoft.OneDrive",
            url: URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!,
            mode: .redirectFilename,
            versionPattern: #"/Installers/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onedrive/download")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/sharepoint/sync-release-notes")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!),
                kind: .pkg),
            followRedirects: false),
        ],
        changelogs: [
        // OneDrive's sync release notes, one page for Windows and macOS. The macOS
        // part is `<h2 id="macos-production-ring">` followed by one
        // `<h4>26.173.0906.0008 (September 25, 2026)</h4>` + `<ul>` per release,
        // newest first, and then `<h2 id="macos-deferred-ring">` with older builds.
        // The Windows rings above it use the same `<h4>` shape and the same
        // versions, and the `<h4>` ids differ only by a de-duplication suffix, so
        // neither can pick out the macOS entries. The entry pattern does: the first
        // entry must follow the macOS Production heading, and every later one must
        // start exactly where the previous match ended (`\G`, ICU), which holds only
        // while consecutive `<h4>` blocks follow each other. The chain ends at the
        // Deferred `<h2>`.
        //
        // Version is the first three components, the probe's scheme and the
        // installed CFBundleShortVersionString (`26.173.0906`); the fourth is a
        // build revision neither carries.
        //
        // Some releases nest a list under "New features gradually rolling out:".
        // An item ends at its own `</li>` or at a nested `<ul>`, so that lead-in
        // and each nested feature come out as separate lines.
        ChangelogRecipe(
            bundleID: "com.microsoft.OneDrive",
            source: URL(string: "https://learn.microsoft.com/en-us/sharepoint/sync-release-notes")!,
            entryPattern:
                #"(?:<h2 id="macos-production-ring">[^<]*</h2>|\G)\s*"#
                + #"<h4 id="[^"]*">(?<version>[0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+\s*\((?<date>[^)<]+)\)</h4>"#
                + #"(?<body>.*?)(?=<h[1-4][\s>]|</main>)"#,
            itemPatterns: [
                #"<li>(?<item>(?:(?!<li>|</li>|<ul>).)*?)(?:</li>|<ul>)"#
            ],
            maxEntries: 30),
        ])
}
