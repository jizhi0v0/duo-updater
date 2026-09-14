import Foundation

enum com_sublimemerge {
    static let set = AppRecipeSet(
        family: "com-sublimemerge",
        probes: [
        // History: docs/app-audits/com-sublimemerge.md#历史与实测
        // Sublime Merge — self-updates, so it reaches us here. NOTE: HTML scrape
        // (mirrors the Sublime Text 4 recipe in
        // `Recipes/com-sublimetext-4.swift` — same vendor, same page shape, and
        // the same bare-number JSON update check, here
        // `sublimemerge.com/updates/stable_update_check`). The /download page's
        // latest marker (e.g. `<p class="latest"><i>Version:</i> Build 2125</p>`)
        // precedes the descending history, so the anchored "Build NNNN" is newest.
        // CRITICAL: capture the FULL "Build NNNN" string — installed
        // CFBundleShortVersionString is literally of the form "Build 2125", and a
        // bare "2125" would read as a perpetual phantom update (VersionComparator
        // ranks a number above adjacent text).
        // Builds are 2xxx (not 4xxx like Sublime Text); the class="latest" anchor
        // already makes it single-match.
        VendorProbeRecipe(
            bundleID: "com.sublimemerge",
            url: URL(string: "https://www.sublimemerge.com/download")!,
            mode: .responseBody,
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+[0-9]+)"#,
            changelogURL: URL(string: "https://www.sublimemerge.com/download"),
            // Same shape as Sublime Text: the page ships the download link as the
            // literal template `sublime_merge_build_${version}_mac.zip` for JS to
            // fill, so it's rebuilt from the same "latest" marker, taking the BARE
            // build number (the version keeps its "Build " prefix to match what the
            // bundle reports; a URL can't carry it).
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.sublimetext.com/sublime_merge_build_{0}_mac.zip",
                    fields: [#"class="latest"><i>Version:</i>\s*Build\s+([0-9]{4})"#]),
                kind: .zip)),
        ])
}
