import Foundation

enum com_ScooterSoftware_BeyondCompare {
    static let set = AppRecipeSet(
        family: "com-ScooterSoftware-BeyondCompare",
        probes: [
        // History: docs/app-audits/com-ScooterSoftware-BeyondCompare.md#历史与实测
        // Beyond Compare (Scooter Software, Team BS29TEJF86). No Sparkle feed and
        // an `auto_updates` cask, so no generic source answers. The app's own
        // "Check for Updates" asks `checkupdates.php?product=bc5&minor=…&maint=…
        // &build=…`, which needs the INSTALLED version in its query and answers
        // an HTML dialog; these probes read the vendor's download pages instead,
        // the build anyone downloads by hand (the same zip that dialog links).
        //
        // Two generations share the bundle id `com.ScooterSoftware.BeyondCompare`
        // and the Team, and crossing them is a paid upgrade (the vendor's upgrade
        // policy: minor and maintenance updates are free, a major version needs a
        // new key). So one probe per generation, each gated with
        // `installedVersionPattern`, and each `versionPattern` pinned to its own
        // major: `/download` is a "newest generation" page, so when a BC6 ships
        // there the BC5 probe fails closed (a failed row in `duo verify`) instead
        // of offering BC5 copies a paid upgrade as a point release.
        //
        // The marketing version is four parts and carries the build
        // (`5.2.6.32774`), the same string as the zip's name, so the default
        // marketing comparison applies. Install: the zip at
        // `/files/BCompareOSX-<version>.zip`, built from the resolved version; its
        // root is `Beyond Compare.app`, notarized, Developer ID Team BS29TEJF86.
        // The bundle carries only a Finder Sync extension (`BCFinder.appex`) inside
        // itself, no helper app, login item or daemon.
        VendorProbeRecipe(
            bundleID: "com.ScooterSoftware.BeyondCompare",
            url: URL(string: "https://www.scootersoftware.com/download")!,
            mode: .responseBody,
            versionPattern: #"href="/files/BCompareOSX-(5\.[0-9]+\.[0-9]+\.[0-9]+)\.zip""#,
            downloadURL: URL(string: "https://www.scootersoftware.com/download"),
            changelogURL: URL(string: "https://www.scootersoftware.com/download/v5changelog"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://www.scootersoftware.com/files/BCompareOSX-{version}.zip"),
                kind: .zip),
            variant: "bc5",
            installedVersionPattern: #"^5\."#),

        // Beyond Compare 4 — end of life, still downloadable from `/download/v4`
        // (the vendor's own update check offers 4.x copies the last 4.x, never
        // BC5). Intel-only builds; same zip layout, same Team.
        VendorProbeRecipe(
            bundleID: "com.ScooterSoftware.BeyondCompare",
            url: URL(string: "https://www.scootersoftware.com/download/v4")!,
            mode: .responseBody,
            versionPattern: #"href="/files/BCompareOSX-(4\.[0-9]+\.[0-9]+\.[0-9]+)\.zip""#,
            downloadURL: URL(string: "https://www.scootersoftware.com/download/v4"),
            changelogURL: URL(string: "https://www.scootersoftware.com/download/v4changelog"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://www.scootersoftware.com/files/BCompareOSX-{version}.zip"),
                kind: .zip),
            variant: "bc4",
            installedVersionPattern: #"^4\."#),
        ],
        changelogs: [
        // One server-rendered page per generation, newest first, every release in
        // `<div class="changelog">`: `<h2>5.2.6.32774 - September 24, 2026</h2>`,
        // then `<h4>` sections, each over a `<ul>`. An entry runs to the next
        // release `<h2>` or the `</div>` that closes the list. The pages cover all
        // platforms; items keep the vendor's "Windows:"/"Linux:" prefix.
        ChangelogRecipe(
            bundleID: "com.ScooterSoftware.BeyondCompare",
            source: URL(string: "https://www.scootersoftware.com/download/v5changelog")!,
            entryPattern: entryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            headingPattern: #"<h4[^>]*>(?<heading>[^<]+)</h4>"#,
            minimumAppVersion: "5", belowAppVersion: "6"),

        ChangelogRecipe(
            bundleID: "com.ScooterSoftware.BeyondCompare",
            source: URL(string: "https://www.scootersoftware.com/download/v4changelog")!,
            entryPattern: entryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            headingPattern: #"<h4[^>]*>(?<heading>[^<]+)</h4>"#,
            minimumAppVersion: "4", belowAppVersion: "5"),
        ])

    private static let entryPattern =
        #"<h2[^>]*>\s*(?<version>[0-9]+(?:\.[0-9]+){3})\s*-\s*(?<date>[^<]*?)\s*</h2>"#
        + #"(?<body>.*?)(?=<h2[^>]*>\s*[0-9]+(?:\.[0-9]+){3}\s*-|</div>)"#
}
