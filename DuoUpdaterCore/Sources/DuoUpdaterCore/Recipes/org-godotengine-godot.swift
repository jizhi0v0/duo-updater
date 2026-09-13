import Foundation

enum org_godotengine_godot {
    static let set = AppRecipeSet(
        family: "org-godotengine-godot",
        githubRules: [
        // Godot — tags are `4.7.1-stable` (and `4.7-stable` for a .0 release), which
        // the default pattern reduces to what the app reports. The release is a wall
        // of platform artifacts; the pattern must exclude `…_mono_macos.universal.zip`,
        // the .NET-enabled build, which is a DIFFERENT distribution of the same
        // bundle id — installing it over a plain install would silently switch the
        // user's editor flavour. One-click: org.godotengine.godot, Team 6K46PWY5DM,
        // notarized.
        GitHubReleaseRule(
            bundleID: "org.godotengine.godot",
            owner: "godotengine", repo: "godot",
            installAssetPattern: #"^Godot_v[0-9.]+-stable_macos\.universal\.zip$"#,
            installerKind: .zip),
        ])
}
