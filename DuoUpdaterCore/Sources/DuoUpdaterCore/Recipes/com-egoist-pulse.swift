import Foundation

enum com_egoist_pulse {
    static let set = AppRecipeSet(
        family: "com-egoist-pulse",
        changelogs: [
        // History: docs/app-audits/com-egoist-pulse.md#历史与实测
        // Detection and one-click come from `MyGoUpdateSource`, which reads the
        // feed and key linked into Pulse's binary (the probe this file used to
        // carry restated both). Only the history of the release notes needs a
        // recipe: the manifest carries the newest release's notes alone.
        //
        // Pulse — the release list of `egoist/pulse-feedback`: each release body
        // is the same text as that release's manifest notes (`mygo build -upload`
        // passes them to `gh release create --notes`), a plain `- ` list.
        ChangelogRecipe(
            bundleID: "com.egoist.pulse",
            source: URL(
                string: "https://api.github.com/repos/egoist/pulse-feedback/releases?per_page=40")!,
            mode: .json,
            maxEntries: 40,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ])
}
