import Foundation

enum com_apple_dt_Xcode {
    static let set = AppRecipeSet(
        family: "com-apple-dt-Xcode",
        changelogs: [
        // History: docs/app-audits/com-apple-dt-Xcode.md#历史与实测
        // Xcode — Apple's own release notes, which `XcodeReleasesSource` already
        // links per release (`links.notes.url` in `xcodereleases.com/data.json`)
        // and which the pane could only ever embed: the `/documentation/…` URL
        // serves an SPA shell with no note text in it.
        // The `/tutorials/data/…` twin of that URL is the document the shell
        // fetches, and it carries everything.
        //
        // One page per release train, and every beta of a train shares its page:
        // the newest beta's notes sit on top, with each earlier beta below it under
        // `Updates in Xcode <major> Beta N`. So a beta install and a
        // released install read the same recipe and differ only in the page the
        // template resolves to — e.g. `26.6` → `xcode-26_6`, `27.0 beta 6` → `xcode-27`.
        // See `appleDocVersionToken(for:)` for why that mapping needs its own token
        // and what `{major}` would get wrong.
        //
        // `source` is only reached when no version is supplied at all (a sweep with
        // no installed Xcode and no detected version); it names the current train,
        // and being a year out of date there costs nothing the templated path uses.
        //
        // Detection-only app, deliberately (an Apple ID gates every prerelease
        // download), so these notes are the whole of what the row can offer beyond
        // a version number.
        ChangelogRecipe(
            bundleID: "com.apple.dt.Xcode",
            source: URL(
                string: "https://developer.apple.com/tutorials/data/documentation"
                    + "/xcode-release-notes/xcode-27-release-notes.json")!,
            mode: .json,
            maxEntries: 20,
            sourceTemplate: "https://developer.apple.com/tutorials/data/documentation"
                + "/xcode-release-notes/xcode-{appleDocVersion}-release-notes.json",
            structuredFormat: .appleDeveloperReleaseNotes),
        ])
}
