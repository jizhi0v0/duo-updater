import Foundation

enum net_sourceforge_grandperspectiv {
    static let set = AppRecipeSet(
        family: "net-sourceforge-grandperspectiv",
        probes: [
        // GrandPerspective — Developer ID (Erwin Bonsma, 3Z75QZGN66), notarized,
        // stapled ticket; `spctl -a -t exec` accepts the mounted app. One-click
        // verified 2026-08-16 against the 3.7.2 dmg: `CFBundleIdentifier` and
        // `CFBundleShortVersionString` on the mounted app match what the probe
        // reports.
        VendorProbeRegistry.sourceForgeMacRecipe(
            bundleID: "net.sourceforge.grandperspectiv",
            project: "grandperspectiv",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/grandperspective/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/GrandPerspective-[0-9_]+\.dmg""#,
            changelogURL: URL(string: "https://sourceforge.net/p/grandperspectiv/news/")!,
            installKind: .dmg),
        ])
}
