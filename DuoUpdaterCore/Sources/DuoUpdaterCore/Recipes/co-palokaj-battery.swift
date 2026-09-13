import Foundation

enum co_palokaj_battery {
    static let set = AppRecipeSet(
        family: "co-palokaj-battery",
        githubRules: [
        // battery — CLI-plus-menu-bar battery limiter. Recent releases ship an
        // arm64 dmg and zip; pin the dmg.
        // One-click: co.palokaj.battery, Team CAWM399GFD, notarized.
        GitHubReleaseRule(
            bundleID: "co.palokaj.battery",
            owner: "actuallymentor", repo: "battery",
            installAssetPattern: #"^battery-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
