import Foundation

enum io_requestly_beta {
    static let set = AppRecipeSet(
        family: "io-requestly-beta",
        changelogs: [
        // Requestly — the release body itself. The repo publishes with
        // conventional commits through GitHub's own release generator, so every
        // body is the auto-generated "## What's Changed" list of `* <commit> by
        // @author in <PR url>` lines followed by "**Full Changelog**: <compare>".
        // `GitHubMarkdownParser` is the parser for exactly that shape: it strips
        // the "by @author in URL" suffix and drops the contributor-noise
        // sections, so `.gitHubReleases` needs no entry/item pattern at all.
        // Most releases carry only the version bump's own commit (two or three
        // lines), which is what the vendor wrote — not a parse failure.
        ChangelogRecipe(
            bundleID: "io.requestly.beta",
            source: URL(string: "https://api.github.com/repos/requestly/http-interceptor-desktop-app/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // Requestly — Electron API client, in the repo GitHub now calls
        // `requestly/http-interceptor-desktop-app`. It updates itself with
        // electron-updater: the bundle's `app-update.yml` says `provider:
        // github`, `releaseType: release`, and `updaterCacheDirName:
        // requestly-updater`, but names the repo by its PRE-RENAME slug
        // (`requestly-desktop-app`), which GitHub still redirects. This rule
        // must use the canonical name: `duo verify` flags the old one as
        // `staleSlug` because riding the redirect costs the request its
        // Authorization header, and the redirect is not permanent.
        // Owner/repo is the one shape `ElectronManifestSource` may not turn into
        // an address — the address would have to be constructed, and a
        // constructed one that answers can belong to someone else — so this rule
        // is the route.
        //
        // Tags read `v26.6.29`; the bundle says 26.6.29, CFBundleVersion the
        // same string. Every release carries `Requestly-<version>-arm64.dmg`
        // beside an arm64 zip (the artifact electron-updater itself downloads),
        // `latest-mac.yml`, and the x64/windows/linux packages. This rule
        // installs the arm64 dmg: io.requestly.beta, Team YQ5FZQ855D,
        // notarized — and the same id and Team in the 26.6.26 build beside it.
        //
        // The `.beta` in the bundle id is NOT a channel. The app ships one
        // release train, marks every release `prerelease: false`, and its updater
        // reads `releaseType: release`. `ReleaseChannel.detect` says so explicitly
        // (step 0.997) because step 2's bundle-id suffix rule would otherwise read
        // every copy as `.beta`, and neither channel could then be served: a
        // stable rule refuses a beta copy, and a `.beta` rule owes a channel proof
        // that this single artifact cannot carry.
        GitHubReleaseRule(
            bundleID: "io.requestly.beta",
            owner: "requestly", repo: "http-interceptor-desktop-app",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^Requestly-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
