import Foundation

enum com_electron_open_lens {
    static let set = AppRecipeSet(
        family: "com-electron-open-lens",
        githubRules: [
        // OpenLens — the build number after the dash IS part of the installed
        // version (`6.5.2-366`), so the pattern captures it; the default would stop
        // at 6.5.2 and read every release as a downgrade. arm64 dmg out of the four
        // macOS artifacts. One-click: com.electron.open-lens, Team HGC72W36QJ,
        // notarized.
        GitHubReleaseRule(
            bundleID: "com.electron.open-lens",
            owner: "MuhammedKalkan", repo: "OpenLens",
            versionPattern: #"v([0-9]+(?:\.[0-9]+)+-[0-9]+)"#,
            installAssetPattern: #"^OpenLens-[0-9.\-]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
