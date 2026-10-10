import Foundation

enum com_microsoft_OneDrive {
    static let set = AppRecipeSet(
        family: "com-microsoft-OneDrive",
        probes: [
        // History: docs/app-audits/com-microsoft-OneDrive.md#历史与实测
        // Microsoft OneDrive — read from the manifest OneDrive's own standalone
        // updater polls for the Production ring, `g.live.com/0USSDMC_W5T/
        // MacODSUProduction`, which 302s to a plist on oneclient.sfx.ms: a
        // `ManifestArray` holding one dict with `CFBundleShortVersionString`,
        // `CFBundleVersion`, `UniversalPkgBinaryURL`, `UniversalPkgSha256Hash`, …
        //
        // Not the "latest" download fwlink (linkid=823060). That link can stay on
        // an older Production build for weeks while this manifest, the release notes
        // and installed copies (which the standalone updater moves) are on a newer
        // one, so a probe on the link reports an up-to-date OneDrive as current
        // when it is not, and its pkg installs that older build.
        //
        // The version is the dict's `CFBundleShortVersionString` (e.g.
        // `26.173.0906`), which is exactly the installed bundle's marketing string.
        // `CFBundleVersion` uses other schemes (`0906.0008` here, `26173.0906.0008`
        // in the bundle), so it is neither read nor compared. A pure re-spin under
        // an unchanged marketing version is invisible — the safe direction (a missed
        // check, never a phantom), and the standalone updater covers it anyway.
        //
        // Install: `UniversalPkgBinaryURL` from the same dict, the universal pkg
        // signed `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`, the
        // same Team as the installed app. `.pkg` because the pkg's install scripts
        // register LaunchDaemons and LaunchAgents (the updater daemons, the sync
        // reporter) outside the bundle. The
        // dict's `UniversalPkgSha256Hash` is base64 SHA-256, a format
        // `VendorInstallSpec.checksumFormat` does not support, so it is not wired.
        // Both patterns take the first match, i.e. the same (only) dict.
        //
        // The dict also carries `Throttle` (100 when last read). Microsoft does not
        // document it; it is not read here.
        VendorProbeRecipe(
            bundleID: "com.microsoft.OneDrive",
            url: URL(string: "https://g.live.com/0USSDMC_W5T/MacODSUProduction")!,
            mode: .responseBody,
            versionPattern: #"<key>CFBundleShortVersionString</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onedrive/download")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/sharepoint/sync-release-notes")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>UniversalPkgBinaryURL</key>\s*<string>(https://oneclient\.sfx\.ms/Mac/Installers/[0-9.]+/universal/OneDrive\.pkg)</string>"#),
                kind: .pkg)),
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
