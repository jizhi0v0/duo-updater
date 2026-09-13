import Foundation

enum io_github_wickenico_wailbrew {
    static let set = AppRecipeSet(
        family: "io-github-wickenico-wailbrew",
        githubRules: [
        // WailBrew — io.github.wickenico.wailbrew, Team 2MC8SWF35Z, notarized.
        // The cask's zap block lists two candidate ids (a rename left `dev.wailbrew`
        // behind); the shipped Info.plist settles it. Note the asset is a zip whose
        // signature only survives `ditto -x -k` — plain `unzip` breaks the seal and
        // makes a good bundle look tampered with.
        GitHubReleaseRule(
            bundleID: "io.github.wickenico.wailbrew",
            owner: "wickenico", repo: "WailBrew",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^wailbrew-v[0-9.]+\.zip$"#,
            installerKind: .zip),
        ])
}
