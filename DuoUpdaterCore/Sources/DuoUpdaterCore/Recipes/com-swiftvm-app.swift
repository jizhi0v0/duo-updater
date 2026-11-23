import Foundation

enum com_swiftvm_app {
    private static let releaseAPI = URL(string: "https://api.github.com/repos/swiftvm-app/swiftvm/releases?per_page=50")!
    private static let channels: [ReleaseChannel] = [.stable, .beta]

    static let set = AppRecipeSet(
        family: "com-swiftvm-app",
        changelogs: channels.map { channel in
            // History: docs/app-audits/com-swiftvm-app.md#历史与实测
            // Sparkle detects updates on separate feeds. The release bodies live
            // on GitHub, where the same list includes rolling feeds and VM images.
            // Scope each recipe to the app's own tags on its installed track.
            ChangelogRecipe(
                bundleID: SwiftVMChannel.bundleID,
                source: releaseAPI,
                mode: .json,
                channel: channel,
                structuredFormat: .gitHubReleases,
                tagPattern: channel == .beta
                    ? #"^v([0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+)$"#
                    : #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#)
        },
        changelogPages: [
            SwiftVMChannel.bundleID: URL(string: "https://github.com/swiftvm-app/swiftvm/releases")!,
        ])
}
