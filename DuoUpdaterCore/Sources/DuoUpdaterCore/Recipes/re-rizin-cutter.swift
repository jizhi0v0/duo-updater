enum re_rizin_cutter {
    static let bundleID = "re.rizin.cutter"
    private static let triplet = #"[0-9]+\.[0-9]+\.[0-9]+"#

    static let set = AppRecipeSet(
        family: "re-rizin-cutter",
        githubRules: [
            // Stable and RC copies both follow GitHub's latest stable release.
            // Signed installations use the usual Developer ID gate. Older
            // ad-hoc RC copies have no Team ID and only get the release link.
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "rizinorg", repo: "cutter",
                versionPattern: #"\Av(\#(triplet))\z"#,
                installAssetPattern: #"\ACutter-v\#(triplet)-macOS-arm64\.dmg\z"#,
                installerKind: .dmg),
        ])

    static func upstreamVersion(from bundleVersion: String) -> String? {
        VendorProbeRecipe.extractVersion(
            from: bundleVersion, pattern: #"\A(\#(triplet))(?:-.+)?\z"#)
    }
}
