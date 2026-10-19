import Foundation

enum com_maxgoedjen_Secretive_Host {
    static let set = AppRecipeSet(
        family: "com-maxgoedjen-Secretive-Host",
        githubRules: [
        // Secretive — SSH keys in the Secure Enclave. No SUFeedURL; its own
        // updater (`Brief/Updater.swift`) reads this repo's releases, skips
        // prereleases, and only notifies (it opens the release page, never
        // installs). v-tags; the release workflow stamps the tag minus `v` into
        // CFBundleShortVersionString (CFBundleVersion is `1.<run id>`). One
        // `Secretive.zip` per release, universal. Team Z72PRUAWF6, notarized.
        //
        // One-click with the agent restarted after the swap. The bundle embeds
        // `Contents/Library/LoginItems/SecretAgent.app`, an `SMAppService` login
        // item and the SSH agent every `ssh` call talks to; it runs while the
        // host app is closed. Left running across a swap, the old agent signs
        // only until its `SecretAgentInputParser.xpc` relaunches from the new
        // bundle; the new XPC refuses the old agent on its code-signing
        // requirement and every `ssh` signing request hangs (audit, 「一键安装」).
        // `loginItemAgentRestarts` below has the engine end the old agent right
        // after the swap; launchd starts it again from the new bundle
        // (`LoginItemAgentRestart`). An agent Secretive started through
        // LaunchServices (its fallback when the login item is not running) is
        // not a launchd job, so it is left alone and reported instead.
        GitHubReleaseRule(
            bundleID: "com.maxgoedjen.Secretive.Host",
            owner: "maxgoedjen", repo: "secretive",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Secretive\.zip$"#,
            installerKind: .zip),
        ],
        loginItemAgentRestarts: [
            "com.maxgoedjen.Secretive.Host": ["com.maxgoedjen.Secretive.SecretAgent"],
        ])
}
