import Foundation

enum com_mongodb_compass {
    static let set = AppRecipeSet(
        family: "com-mongodb-compass",
        probes: [
        // MongoDB Compass — the vendor's own download-center JSON
        // (`s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json`,
        // status 200, 7814 bytes when checked 2026-08-16). `versions` is
        // newest-first (a single current entry in practice); `versions[0]._id`
        // read `1.49.14`, matching BOTH `CFBundleShortVersionString` and
        // `CFBundleVersion` of the mounted arm64 dmg — no `versionIsBuild` needed.
        // The same entry's `platform` array carries a `download_link` per
        // arch/os; the arm64/darwin one is captured directly (no template
        // needed, unlike GIMP). No checksum is published in this feed.
        // Installed-bundle identity confirmed 2026-08-16: `com.mongodb.compass`,
        // notarized Developer ID, Team 4XWMY46275 (MongoDB, Inc.) — `spctl`
        // accepted as "Notarized Developer ID".
        VendorProbeRecipe(
            bundleID: "com.mongodb.compass",
            url: URL(string: "https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json")!,
            mode: .responseBody,
            versionPattern: #""_id"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.mongodb.com/try/download/compass"),
            changelogURL: URL(string: "https://www.mongodb.com/docs/compass/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""arch"\s*:\s*"arm64"\s*,\s*"os"\s*:\s*"darwin"\s*,\s*"name"\s*:\s*"[^"]*"\s*,\s*"download_link"\s*:\s*"([^"]+)""#),
                kind: .dmg)),
        ])
}
