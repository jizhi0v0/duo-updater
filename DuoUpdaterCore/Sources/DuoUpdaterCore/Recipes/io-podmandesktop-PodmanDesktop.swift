import Foundation

enum io_podmandesktop_PodmanDesktop {
    static let set = AppRecipeSet(
        family: "io-podmandesktop-PodmanDesktop",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Podman Desktop — the release also carries `podman-desktop-airgap-<ver>-
        // arm64.dmg`, a 1.1 GB bundle-everything build. The `^podman-desktop-<ver>-`
        // anchor keeps the airgap variant out; without it a substring match would
        // hand the user a gigabyte download for the same app.
        // One-click: io.podmandesktop.PodmanDesktop, Team HYSCB8KRL2, notarized.
        //
        // ⚠️ Renamed containers/podman-desktop
        // -> podman-desktop/podman-desktop (measured 2026-08-29). The canonical
        // name is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
        // whatever token the user configured. Three rules were quietly doing
        // that. See #135.
        GitHubReleaseRule(
            bundleID: "io.podmandesktop.PodmanDesktop",
            owner: "podman-desktop", repo: "podman-desktop",
            installAssetPattern: #"^podman-desktop-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
