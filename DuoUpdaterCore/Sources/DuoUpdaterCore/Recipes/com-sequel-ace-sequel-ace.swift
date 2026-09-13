import Foundation

enum com_sequel_ace_sequel_ace {
    static let set = AppRecipeSet(
        family: "com-sequel-ace-sequel-ace",
        githubRules: [
        // Sequel Ace — tags are `production/5.4.0-20109` (marketing version plus the
        // build number); the default pattern's first match is the marketing version,
        // which is what the app reports. `beta/…` tags and some respun `production/…`
        // tags are published as prereleases, so `/releases/latest` is what keeps a
        // stable install on the production train.
        // One-click: com.sequel-ace.sequel-ace, Team NKQ4HJ66PX, notarized.
        GitHubReleaseRule(
            bundleID: "com.sequel-ace.sequel-ace",
            owner: "Sequel-Ace", repo: "Sequel-Ace",
            installAssetPattern: #"^Sequel-Ace-[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
