import Foundation

enum com_federicoterzi_espanso {
    static let set = AppRecipeSet(
        family: "com-federicoterzi-espanso",
        githubRules: [
        // Espanso — text expander. The macOS asset name carries NO version
        // (`Espanso-Mac-Universal.dmg`), so the pattern is a literal. Older releases
        // shipped the same name as a .zip; if upstream flips back, the install URL
        // simply resolves nothing (a warning) instead of grabbing a wrong artifact.
        // One-click: com.federicoterzi.espanso, Team 6424323YUH, notarized.
        GitHubReleaseRule(
            bundleID: "com.federicoterzi.espanso",
            owner: "espanso", repo: "espanso",
            installAssetPattern: #"^Espanso-Mac-Universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
