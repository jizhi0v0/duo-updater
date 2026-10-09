import Foundation

enum com_voprex_gotemail {
    static let set = AppRecipeSet(
        family: "com-voprex-gotemail",
        changelogs: [
        // GotEmail — `releases.json`, not the appcast's own notes.
        //
        // Detection and one-click need nothing here: the bundle declares
        // `SUFeedURL` (`gotemail.shipcat.app/appcast.xml`) and the generic Sparkle
        // source reads it. That feed carries only the newest release, and its
        // inline notes open with an `<h2>GotEmail <version></h2>` that the pane
        // shows as a change line. `releases.json` is the file the vendor's What's
        // New page (`/whatsnew/`) renders: every release, each line tagged.
        ChangelogRecipe(
            bundleID: "com.voprex.gotemail",
            source: URL(string: "https://gotemail.shipcat.app/releases.json")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gotEmailReleases),
        ])
}
