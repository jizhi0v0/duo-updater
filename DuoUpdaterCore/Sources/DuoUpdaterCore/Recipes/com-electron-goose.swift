import Foundation

enum com_electron_goose {
    static let set = AppRecipeSet(
        family: "com-electron-goose",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // Goose (aaif-goose/goose) — the `goose-*-apple-darwin.tar.gz` assets beside
        // the app are the CLI and `goose-source-*.zip` is a source drop, so the app is
        // anchored by literal name. BOTH macOS builds are matched: `Goose.zip` is
        // arm64-ONLY (checked with `file`: a single arm64 slice, not a universal
        // binary) and `Goose_intel_mac.zip` is the Intel build. Matching only
        // `Goose.zip` would look arch-neutral to `installableAsset` — the name
        // carries no arch token — so an Intel Mac would be handed an arm64 app that
        // cannot launch, and the install gate would not catch it (it checks
        // signature, Team and bundle id, never architecture). With both matched the
        // arch preference resolves it: `intel` is an x86_64 token, so an Intel Mac
        // takes `Goose_intel_mac.zip` while Apple silicon falls through to the
        // token-free `Goose.zip`.
        // One-click: com.electron.goose, Team 5N2JF58U87, notarized — verified on
        // BOTH assets.
        //
        // ⚠️ Renamed block/goose
        // -> aaif-goose/goose (measured 2026-08-29). The canonical name
        // is pinned here on purpose, and it is not cosmetic: GitHub answers the
        // old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
        // `Authorization` while following it — the fetch that actually returns
        // the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
        // whatever token the user configured. Three rules were quietly doing
        // that. See #135.
        GitHubReleaseRule(
            bundleID: "com.electron.goose",
            owner: "aaif-goose", repo: "goose",
            installAssetPattern: #"^Goose(_intel_mac)?\.zip$"#,
            installerKind: .zip),
        ])
}
