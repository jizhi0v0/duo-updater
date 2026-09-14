import Foundation

enum com_electron_goose {
    static let set = AppRecipeSet(
        family: "com-electron-goose",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/com-electron-goose.md#历史与实测
        // Goose (aaif-goose/goose) — the `goose-*-apple-darwin.tar.gz` assets beside
        // the app are the CLI and `goose-source-*.zip` is a source drop, so the app is
        // anchored by literal name. BOTH macOS builds are matched: `Goose.zip` is
        // arm64-ONLY (checked with `file`: a single arm64 slice, not a universal
        // binary) and `Goose_intel_mac.zip` is the Intel build. `Goose.zip` carries
        // no arch token, so `installableAsset` reads it as arch-neutral; with both
        // matched the arch preference picks between them: `intel` is an x86_64
        // token, so Apple silicon — the only host DuoUpdater runs on
        // (`App/project.yml`) — takes the token-free `Goose.zip`. Whatever the name
        // says, the install gate reads the downloaded bundle's real architectures
        // (`SignatureVerifier.verifyRunnableArchitecture`).
        // One-click: com.electron.goose, Team 5N2JF58U87, notarized — verified on
        // BOTH assets.
        //
        // ⚠️ Renamed block/goose -> aaif-goose/goose. The canonical name
        // is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases comes back ANONYMOUS, whatever token the user configured.
        // See #135.
        GitHubReleaseRule(
            bundleID: "com.electron.goose",
            owner: "aaif-goose", repo: "goose",
            installAssetPattern: #"^Goose(_intel_mac)?\.zip$"#,
            installerKind: .zip),
        ])
}
