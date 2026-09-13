import Foundation

enum io_ganeshrvel_openmtp {
    static let set = AppRecipeSet(
        family: "io-ganeshrvel-openmtp",
        githubRules: [
        // OpenMTP — Android file transfer. arm64/x64 dmgs and zips of the same build
        // ship together; pin the arm64 dmg.
        // One-click: io.ganeshrvel.openmtp, Team 6UR4H85SA2, notarized.
        GitHubReleaseRule(
            bundleID: "io.ganeshrvel.openmtp",
            owner: "ganeshrvel", repo: "openmtp",
            installAssetPattern: #"^openmtp-[0-9.]+-mac-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
