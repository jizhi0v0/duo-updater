import Foundation

enum com_tigervnc_tigervnc {
    static let set = AppRecipeSet(
        family: "com-tigervnc-tigervnc",
        probes: [
        // TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
        // accepts the mounted app. One-click verified 2026-08-16 against the
        // 1.16.0 dmg the same way.
        VendorProbeRegistry.sourceForgeMacRecipe(
            bundleID: "com.tigervnc.tigervnc",
            project: "tigervnc",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/TigerVNC-[0-9.]+\.dmg""#,
            changelogURL: URL(string: "https://github.com/TigerVNC/tigervnc/releases")!,
            installKind: .dmg),
        ])
}
