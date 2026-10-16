import Foundation

enum Jellyfin_Server {
    static let set = AppRecipeSet(
        family: "Jellyfin-Server",
        probes: [
        // History: docs/app-audits/Jellyfin-Server.md#历史与实测
        // Jellyfin Server — the media server's macOS wrapper (`Jellyfin.app`,
        // bundle id `Jellyfin.Server`, built from jellyfin/jellyfin-server-macos):
        // an `LSUIElement` menu-bar launcher that starts the bundled `jellyfin`
        // server as its own child `Process` and terminates it, waiting for it to
        // exit, in `applicationWillTerminate`. No Sparkle, no updater of any kind.
        //
        // The vendor publishes macOS builds only on its own file server, never as
        // GitHub release assets (the jellyfin/jellyfin releases carry notes and no
        // files), so a GitHub rule cannot see them. This reads the nginx index of
        // `latest-stable/arm64/`, which holds exactly one release's dmg and tar.xz.
        // The pattern takes the dmg's filename only: rc builds live under
        // `preview/` and are named `jellyfin_<ver>-rc<N>-arm64.dmg`, unstable
        // builds under `unstable/` are tar.xz only and numbered by date, and the
        // `-rc` / bare-date shapes cannot match `<digits>(.<digits>)+-arm64.dmg`.
        // Versions are three-part up to 10.11.x and two-part from 12.0; both read.
        //
        // The dmg filename's version equals the bundle's CFBundleShortVersionString
        // (and CFBundleVersion). The arm64 dmg's server binary is arm64 only (its
        // launcher is universal); DuoUpdater runs on arm64 only, so the amd64 dmg
        // is never wanted. This is the newest build on the vendor's stable track,
        // the same file the cask and the download page hand everyone; there is no
        // per-machine allocation.
        VendorProbeRecipe(
            bundleID: "Jellyfin.Server",
            url: URL(string: "https://repo.jellyfin.org/files/server/macos/latest-stable/arm64/")!,
            mode: .responseBody,
            versionPattern: #"href="jellyfin_([0-9]+(?:\.[0-9]+)+)-arm64\.dmg""#,
            downloadURL: URL(string: "https://jellyfin.org/downloads/server"),
            changelogURL: URL(string: "https://github.com/jellyfin/jellyfin/releases"),
            // ONE-CLICK. The URL is built from the version that was compared, on
            // the immutable per-version path (`stable/v<ver>/arm64/`), not the
            // `latest-stable/` alias, which moves on the next release. The file
            // server 302s to a geo mirror. Every release from 10.7.7 to 12.2 is
            // `Jellyfin.Server`, Team 6YC6EAV7ES, notarized Developer ID. The
            // index publishes no digest, so the install is Team-ID gated only.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://repo.jellyfin.org/files/server/macos/stable/v{version}/arm64/jellyfin_{version}-arm64.dmg"),
                kind: .dmg)),
        ],
        changelogs: [
        // Jellyfin Server — notes are the GitHub release bodies of
        // jellyfin/jellyfin: Markdown, a `## Changelog (N)` heading then `###`
        // sections of `* <change> [PR #…], by @…` lines. Tags are `v<version>`,
        // the same string the dmg and the bundle carry. Release candidates are
        // flagged as GitHub prereleases.
        ChangelogRecipe(
            bundleID: "Jellyfin.Server",
            source: URL(string: "https://api.github.com/repos/jellyfin/jellyfin/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),
        ])
}
