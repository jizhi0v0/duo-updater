import Foundation

enum phpstudy_xpfme_com {
    static let set = AppRecipeSet(
        family: "phpstudy-xpfme-com",
        githubRules: [
        // FlyEnv — Electron environment manager for PHP/Node/local servers, with
        // the vendor's own domain as its bundle id (`phpstudy.xpfme.com`; the
        // Homebrew cask's zap list still names the app's earlier PhpWebStudy
        // paths). It updates itself with electron-updater: `app-update.yml` says
        // `provider: github`, this owner/repo, and `updaterCacheDirName:
        // flyenv-updater`. Owner/repo is the shape `ElectronManifestSource` may
        // not construct an address from, so this rule is the route.
        //
        // Tags read `v4.20.2`; the bundle says 4.20.2. Each release carries
        // `FlyEnv-<version>-arm64-mac.zip` and `FlyEnv-<version>-arm64.dmg`
        // (electron-updater's own artifacts, with `.blockmap` beside them)
        // among the .deb/.rpm/windows packages. This rule installs the zip,
        // which is the artifact the app's updater and the Homebrew cask both
        // take: phpstudy.xpfme.com, Team 956BZQ2F2P, notarized.
        GitHubReleaseRule(
            bundleID: "phpstudy.xpfme.com",
            owner: "xpf0000", repo: "FlyEnv",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^FlyEnv-[0-9]+(?:\.[0-9]+)+-arm64-mac\.zip$"#,
            installerKind: .zip),
        ])
}
