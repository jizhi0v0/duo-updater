import Foundation

enum io_requestly_beta {
    static let set = AppRecipeSet(
        family: "io-requestly-beta",
        githubRules: [
        // Requestly — HTTP interception proxy (Electron), BrowserStack. The
        // stable app has shipped as `io.requestly.beta` since at least v1.4.0.
        // The repo was renamed from requestly/requestly-desktop-app; the
        // bundle's app-update.yml still names the old one, which GitHub
        // redirects. Its own updater is electron-updater (provider github,
        // library defaults: downloads on its own, installs through Squirrel
        // on quit, cache dir `requestly-updater`, which SelfUpdaterStash
        // reads). No login item or LaunchAgent ships. The root CA it asks the
        // user to trust lives in the login keychain and under
        // ~/Library/Application Support/Requestly, and the system proxy is
        // set with `networksetup` from the running process; none of it is in
        // the bundle, so a swap leaves both as they were.
        //
        // Tags read `v26.6.29`; the bundle says 26.6.29. Each release has an
        // arm64 dmg/zip and an x64 dmg/zip (no arch word), no universal.
        // Team YQ5FZQ855D from v25.6.27; v25.6.25 and older are AFBT5Z9V94,
        // so gate 3 refuses one-click for those copies (detection only).
        GitHubReleaseRule(
            bundleID: "io.requestly.beta",
            owner: "requestly", repo: "http-interceptor-desktop-app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Requestly-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
