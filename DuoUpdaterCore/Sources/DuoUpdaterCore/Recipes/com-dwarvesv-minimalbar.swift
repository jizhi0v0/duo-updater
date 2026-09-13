import Foundation

enum com_dwarvesv_minimalbar {
    static let set = AppRecipeSet(
        family: "com-dwarvesv-minimalbar",
        githubRules: [
        // Hidden Bar — the app DOES carry a Sparkle feed
        // (`SUFeedURL = api.amore.computer/v1/apps/com.dwarvesv.minimalbar/appcast.xml`),
        // which is why it looks covered from the outside and isn't: fetched
        // 2026-08-16 the feed answers 200 with a well-formed `<channel>` — title,
        // link, description — and **no `<item>` at all**. `SparkleAppcastSource`
        // finds nothing, returns nil, and the row falls through to here as
        // "unknown" with nothing failing anywhere. An empty feed is exactly the
        // shape a broken recipe can't be told from a healthy one, so the version
        // comes from the tags instead, which are real (`v1.10`).
        //
        // One-click verified 2026-08-16 by unpacking `Hidden-Bar-v1.10-macos.zip`:
        // `Hidden Bar.app`, com.dwarvesv.minimalbar, 1.10, universal, Team
        // W777S7V8TN (Dwarves Foundation Company Limited), notarized Developer ID.
        GitHubReleaseRule(
            bundleID: "com.dwarvesv.minimalbar",
            owner: "dwarvesf", repo: "hidden",
            installAssetPattern: #"^Hidden-Bar-v[0-9.]+-macos\.zip$"#,
            installerKind: .zip),
        ])
}
