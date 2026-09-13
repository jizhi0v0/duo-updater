import Foundation

enum dev_openchamber_desktop {
    static let set = AppRecipeSet(
        family: "dev-openchamber-desktop",
        githubRules: [
        // OpenChamber — electron-builder publishes both architectures beside
        // Windows/Linux/mobile artifacts. Keep the extension and mac token
        // anchored; the architecture-aware selector chooses arm64 or x64.
        // Mounted arm64 dmg: dev.openchamber.desktop, Team 5J7WJGPA2Q, notarized.
        GitHubReleaseRule(
            bundleID: "dev.openchamber.desktop",
            owner: "openchamber", repo: "openchamber",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$"#,
            installerKind: .dmg),
        ])
}
