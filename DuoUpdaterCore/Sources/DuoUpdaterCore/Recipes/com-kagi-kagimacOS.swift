import Foundation

enum com_kagi_kagimacOS {
    static let set = AppRecipeSet(
        family: "com-kagi-kagimacOS",
        probes: [
        // Orion (Kagi) — official Sparkle appcast under the macOS-major flavor dir
        // (`26_0`, the same path the Homebrew cask download uses; the bare
        // /updates/appcast.xml is a STALE stub frozen at 1.0.0 — don't use it). The
        // feed lists releases ASCENDING, so selectHighest (not first match, which is
        // the oldest 0.99) picks the current build. We extract
        // `sparkle:shortVersionString` (MARKETING version, e.g. 1.0.8) — NOT
        // `sparkle:version` (the build, e.g. 147/147.1). A vendor probe can only
        // populate `shortVersion`, so UpdateChecker compares against the installed
        // CFBundleShortVersionString (1.0.8); feeding the build "147.1" would compare
        // 147 > 1 and invent a permanent phantom update. Trade-off: blind to a
        // build-only rebuild at an unchanged marketing version — the conservative,
        // never-lie choice. One-click: the feed is ASCENDING, so the install takes
        // the LAST `<enclosure url=…zip>` (newest) — `.bodyPatternLast`, mirroring
        // `selectHighest` on the version side; first-match would grab the oldest 0.99.
        // (Orion self-updates via Sparkle; fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "com.kagi.kagimacOS",
            url: URL(string: "https://cdn.kagi.com/updates/26_0/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+)+)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://browser.kagi.com/"),
            changelogURL: URL(string: "https://browser.kagi.com/updates/orion-release-notes.html"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(#"url="(https://[^"]+\.zip)""#),
                kind: .zip)),
        ])
}
