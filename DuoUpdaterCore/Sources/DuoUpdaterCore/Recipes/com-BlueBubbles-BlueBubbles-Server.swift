import Foundation

enum com_BlueBubbles_BlueBubbles_Server {
    static let set = AppRecipeSet(
        family: "com-BlueBubbles-BlueBubbles-Server",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // BlueBubbles server — Developer ID signed (Team WPV275H8W7) but NOT
        // notarized, so the gate rejects it.
        GitHubReleaseRule(
            bundleID: "com.BlueBubbles.BlueBubbles-Server",
            owner: "BlueBubblesApp", repo: "bluebubbles-server"),
        ])
}
