import Foundation

enum com_qvacua_VimR {
    static let set = AppRecipeSet(
        family: "com-qvacua-VimR",
        changelogs: [
        // History: docs/app-audits/com-qvacua-VimR.md#历史与实测
        // VimR — GitHub releases, not the appcast's own notes. VimR's
        // `bin/set_appcast.py` writes each appcast as ONE item whose
        // `<description>` is `markdown.markdown(<the GitHub release body>)`, so
        // the feed only ever shows the version being offered. The release list
        // carries the same bullets and the history.
        //
        // The vendor writes flat bullet lists (sub-bullets for dependency
        // bumps) with no section headings, so entries have no headings to keep.
        //
        // The repository also publishes `neovim-v<nvim>-<build>` prereleases
        // (bare nvim tarballs), `snapshot/<build>` prereleases and the odd
        // `vimr-deps-…` tag. The tag pattern admits only the stable shape,
        // `v<marketing>-<yyyymmdd>.<hhmmss>`, and captures the marketing
        // version, which is the bundle's `CFBundleShortVersionString`.
        //
        // Not for a snapshot copy (`VimRChannel` → `.preview`): the snapshot
        // appcast can offer a `snapshot/<build>` prerelease, which this list
        // leaves out, so the pane would show stable notes for a build the user is
        // not being offered. Excluded, it falls back to the snapshot feed's own
        // inline notes, which always describe the offered item.
        ChangelogRecipe(
            bundleID: "com.qvacua.VimR",
            source: URL(string: "https://api.github.com/repos/qvacua/vimr/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            excludedChannels: [.preview],
            structuredFormat: .gitHubReleases,
            tagPattern: #"^v([0-9]+(?:\.[0-9]+)+)-[0-9]{8}\.[0-9]{6}$"#),
        ],
        bindingProofs: [
        // VimR — `VimRChannel` swaps in the snapshot appcast when the user ticks
        // "use snapshot updates". Request-keyed like IINA: nothing in the feed
        // names the track, so the proof is the address we asked for.
        ChannelProofKey("com.qvacua.VimR", .preview):
            .recipeAnchor(#"appcast_snapshot\.xml"#, in: ["feedOverride"]),
        ])
}
