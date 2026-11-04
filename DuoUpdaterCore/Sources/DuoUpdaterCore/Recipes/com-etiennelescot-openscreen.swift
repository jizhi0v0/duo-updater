import Foundation

enum com_etiennelescot_openscreen {
    static let set = AppRecipeSet(
        family: "com-etiennelescot-openscreen",
        changelogs: [
        // OpenScreen — detection comes from the Homebrew cask (`openscreen`, with
        // `auto_updates` unset), which supplies a version and no notes; the
        // bundle's electron-builder `app-update.yml` is only written into the
        // installed copy and does not carry notes either.
        //
        // Releases are tagged `v2.2.1` and carry the changelog in the body. The
        // repo also publishes `-rc.N` prereleases, which `.gitHubReleases` keeps
        // out (it reads stable releases only), so no extra tag pattern is needed.
        ChangelogRecipe(
            bundleID: "com.etiennelescot.openscreen",
            source: URL(
                string:
                    "https://api.github.com/repos/getopenscreen/openscreen/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ])
}
