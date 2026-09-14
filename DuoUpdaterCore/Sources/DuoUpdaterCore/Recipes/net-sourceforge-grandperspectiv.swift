import Foundation

enum net_sourceforge_grandperspectiv {
    static let set = AppRecipeSet(
        family: "net-sourceforge-grandperspectiv",
        probes: [
        // History: docs/app-audits/net-sourceforge-grandperspectiv.md#历史与实测
        // GrandPerspective — Developer ID (Erwin Bonsma, 3Z75QZGN66), notarized,
        // stapled ticket; `spctl -a -t exec` accepts the mounted app. One-click:
        // `CFBundleIdentifier` and `CFBundleShortVersionString` on the mounted app
        // match what the probe reports (checked 2026-08-16; History has the dmg
        // version).
        VendorProbeRegistry.sourceForgeMacRecipe(
            bundleID: "net.sourceforge.grandperspectiv",
            project: "grandperspectiv",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/grandperspective/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/GrandPerspective-[0-9_]+\.dmg""#,
            changelogURL: URL(string: "https://sourceforge.net/p/grandperspectiv/news/")!,
            installKind: .dmg),
        ])
}
