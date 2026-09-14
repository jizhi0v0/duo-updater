import Foundation

enum com_tigervnc_tigervnc {
    static let set = AppRecipeSet(
        family: "com-tigervnc-tigervnc",
        probes: [
        // History: docs/app-audits/com-tigervnc-tigervnc.md#历史与实测
        // TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
        // accepts the app mounted from the one-click dmg (checked 2026-08-16;
        // History has the dmg version).
        VendorProbeRegistry.sourceForgeMacRecipe(
            bundleID: "com.tigervnc.tigervnc",
            project: "tigervnc",
            versionPattern:
                #""mac":\s*\{[^}]*?"filename":\s*"/stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/TigerVNC-[0-9.]+\.dmg""#,
            changelogURL: URL(string: "https://github.com/TigerVNC/tigervnc/releases")!,
            installKind: .dmg),
        ])
}
