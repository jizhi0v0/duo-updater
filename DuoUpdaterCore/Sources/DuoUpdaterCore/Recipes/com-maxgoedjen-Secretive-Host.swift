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
        // DETECTION-ONLY, although the zip would pass the install gate: the
        // bundle embeds `Contents/Library/LoginItems/SecretAgent.app`, the SSH
        // agent every `ssh` call talks to. It is an accessory process, so
        // `AppRestarter` neither quits nor relaunches it, and nothing here
        // restarts it after the swap; the vendor relies on the host app
        // relaunching it on its next activation. Until that happens the agent
        // keeps running the old code while its bundle has been replaced on disk,
        // and whether SSH signing keeps working then has not been shown. The user
        // updates by hand, as the vendor's own flow expects.
        GitHubReleaseRule(
            bundleID: "com.maxgoedjen.Secretive.Host",
            owner: "maxgoedjen", repo: "secretive",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
        ])
}
