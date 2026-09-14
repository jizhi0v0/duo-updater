import Foundation

enum io_beekeeperstudio_desktop {
    static let set = AppRecipeSet(
        family: "io-beekeeperstudio-desktop",
        githubRules: [
        // History: docs/app-audits/io-beekeeperstudio-desktop.md#历史与实测
        // Beekeeper Studio (Community) — tags carry a `v` prefix (e.g. v5.8.1),
        // stripped by the default pattern. Betas ship as `vX.Y.Z-beta.N` flagged
        // prerelease, so usePrereleases=false / `/releases/latest` correctly skips
        // them.
        //
        // Best-effort one-click: the `Beekeeper-Studio-<ver>-arm64.dmg` asset wraps
        // `Beekeeper Studio.app` — a notarized Developer ID build (Team 7KK583U8H2,
        // Matthew Rathbone) reporting the tag as its version, bundle id
        // io.beekeeperstudio.desktop (checked 2026-06-06; History has the version).
        // Electron app with its own updater, so a fallback. The filename carries
        // the version, so the pattern stays version-agnostic; arm64 (the bare `…-<ver>.dmg` is NOT
        // universal — checked with `file` on 6.0.1, it is a single x86_64 slice —
        // and a `-mac.zip` also ships, so the arm64 anchor is what keeps an Intel
        // build off an arm64 Mac). The VendorInstaller Team-gate enforces the match
        // against whatever is installed.
        GitHubReleaseRule(
            bundleID: "io.beekeeperstudio.desktop",
            owner: "beekeeper-studio", repo: "beekeeper-studio",
            installAssetPattern: #"^Beekeeper-Studio-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
