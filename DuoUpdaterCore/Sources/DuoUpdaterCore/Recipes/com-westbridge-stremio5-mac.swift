import Foundation

enum com_westbridge_stremio5_mac {
    static let set = AppRecipeSet(
        family: "com-westbridge-stremio5-mac",
        probes: [
        // Stremio 5 for macOS (closed-source Rust shell, West Bridge Ltd). No
        // Sparkle: the shell's own updater (`src/updater.rs` in its binary) asks
        // `https://www.strem.io/updater/check?product=stremio-shell-macos`
        // (stremio.com and stremio.net are its fallbacks) with the build's arch,
        // and the service answers
        // `{"versionDesc":"https://dl.strem.io/stremio-shell-macos/[versions]/v5.1.28_arm64.json?…","version":"5.1.28"}`.
        // `version` is the marketing string, equal to both Info.plist version
        // fields in every bundle read (5.1.14 – 5.1.28). The query is
        // Homebrew's `stremio@beta` livecheck; the shell's own request was not
        // captured (its `--autoupdater-endpoint` override could do it).
        //
        // TRACK. The updater can answer ahead of the download page (the audit
        // has the case): a copy updates itself to what the updater says, not to
        // what the page links, so that is the version this recipe offers. The
        // shell's `--release-candidate` flag (an `rc` query) is a command-line
        // switch with no setting behind it, so it gets no recipe.
        //
        // ONE-CLICK: the descriptor names `…/v{version}/Stremio_arm64.dmg`, a
        // path that holds for every release read (5.1.16 – 5.1.28): Developer ID
        // West Bridge Ltd, Team BH62GT22G7, notarized, bundle id
        // `com.westbridge.stremio5-mac`, arm64 only, no nested apps, no login
        // items. The x64 dmg is a separate file; DuoUpdater itself runs on Apple
        // silicon only. The descriptor carries a hex SHA-256 of the dmg (equal
        // to a real download), but it is a second request away from this body,
        // so the Team-ID gate is the integrity check.
        VendorProbeRecipe(
            bundleID: "com.westbridge.stremio5-mac",
            url: URL(string: "https://www.stremio.com/updater/check?product=stremio-shell-macos&arch=arm64")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.stremio.com/downloads"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dl.strem.io/stremio-shell-macos/v{version}/Stremio_arm64.dmg"),
                kind: .dmg)),
        // The first v5 builds (5.1.14 read) were `com.stremio.stremio-shell-macos`,
        // ad-hoc signed with no Team ID; 5.1.16 is the first West Bridge build
        // read. Their updater asks the same endpoint and its script replaces
        // /Applications/Stremio.app with whatever the dmg holds, so the vendor
        // moves these copies to the new id. A `BundleIDMigration` can't express
        // it (no Team on the old side), so the old id gets detection only.
        VendorProbeRecipe(
            bundleID: "com.stremio.stremio-shell-macos",
            url: URL(string: "https://www.stremio.com/updater/check?product=stremio-shell-macos&arch=arm64")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.stremio.com/downloads")),
        ])
}
