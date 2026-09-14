import Foundation

enum io_podmandesktop_PodmanDesktop {
    static let set = AppRecipeSet(
        family: "io-podmandesktop-PodmanDesktop",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/io-podmandesktop-PodmanDesktop.md#历史与实测
        // Podman Desktop — the release also carries `podman-desktop-airgap-<ver>-
        // arm64.dmg`, a gigabyte-scale bundle-everything build. The
        // `^podman-desktop-<ver>-` anchor keeps the airgap variant out; without it
        // a substring match would hand the user a gigabyte download for the same
        // app.
        // One-click: io.podmandesktop.PodmanDesktop, Team HYSCB8KRL2, notarized.
        //
        // ⚠️ Renamed containers/podman-desktop -> podman-desktop/podman-desktop.
        // The canonical name is pinned here on purpose, and it is not cosmetic:
        // GitHub answers the old slug with a 301 to `/repositories/<id>/…`, and
        // URLSession drops `Authorization` while following it — the fetch that
        // actually returns the releases comes back ANONYMOUS, whatever token the
        // user configured. See #135.
        GitHubReleaseRule(
            bundleID: "io.podmandesktop.PodmanDesktop",
            owner: "podman-desktop", repo: "podman-desktop",
            installAssetPattern: #"^podman-desktop-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
