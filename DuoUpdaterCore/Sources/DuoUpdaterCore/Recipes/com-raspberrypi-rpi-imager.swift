import Foundation

enum com_raspberrypi_rpi_imager {
    static let set = AppRecipeSet(
        family: "com-raspberrypi-rpi-imager",
        githubRules: [
        // Raspberry Pi Imager — the ONE app here whose own
        // `CFBundleShortVersionString` keeps the `v` (`v2.0.11`), so the pattern
        // captures the `v` too; stripping it (the default) would leave every
        // comparison against a string the app never reports. `-rc` tags are
        // published as prereleases, and `/releases/latest` skips them.
        // One-click: com.raspberrypi.rpi-imager, Team 8RDZTRXE62, notarized.
        GitHubReleaseRule(
            bundleID: "com.raspberrypi.rpi-imager",
            owner: "raspberrypi", repo: "rpi-imager",
            versionPattern: #"^(v[0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^rpi-imager-v[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
