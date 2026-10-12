import Foundation

enum org_rustgis_RustGIS {
    static let set = AppRecipeSet(
        family: "org-rustgis-RustGIS",
        githubRules: [
        // RustGIS (opengeos/RustGIS, Team Z6ABKZWLA7, notarized) — an egui
        // desktop GIS with no SUFeedURL and no in-app updater. release.yml
        // stamps the tag minus `v` into both CFBundleShortVersionString and
        // CFBundleVersion (packaging/macos/Info.plist) and refuses a tag that
        // differs from the Cargo workspace version. A pre-release is tagged
        // `v0.2.0-rc.1`; the anchored pattern keeps those off the stable track.
        // `-macos-aarch64.dmg` and `-macos-x86_64.dmg` ship together; the
        // `downloads.rustgis.app` page is a mirror of the same release assets.
        GitHubReleaseRule(
            bundleID: "org.rustgis.RustGIS",
            owner: "opengeos", repo: "RustGIS",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^RustGIS-[0-9][0-9A-Za-z.-]*-macos-(?:aarch64|x86_64)\.dmg$"#,
            installerKind: .dmg),
        ])
}
