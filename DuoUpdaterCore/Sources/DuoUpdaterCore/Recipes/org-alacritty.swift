import Foundation

enum org_alacritty {
    static let set = AppRecipeSet(
        family: "org-alacritty",
        githubRules: [
        // History: docs/app-audits/org-alacritty.md#历史与实测
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // MARK: No Team ID — detection-only, or digest-only where the build allows
        //
        // Seven rules were added detection-only because their macOS artifact is not
        // a Developer ID build, so the Team-ID gate in `VendorInstaller` would
        // refuse the swap: this file, `Recipes/org-flameshot-Flameshot.swift`,
        // `Recipes/com-github-marktext-marktext.swift`, `Recipes/org-darktable.swift`,
        // `Recipes/org-zaproxy-zap-ZAP.swift`,
        // `Recipes/com-BlueBubbles-BlueBubbles-Server.swift` and
        // `Recipes/org-winehq-wine-staging-wine.swift`.
        //
        // Three of them — Alacritty, Flameshot, darktable — ship an ad-hoc build
        // whose seal verifies (`codesign --verify --deep --strict`), whose signed
        // identifier is its bundle id, and whose version is the tag's. Those are
        // `installTrust: .publishedDigestOnly`: one-click only when the user allows
        // it, checked against the SHA-256 GitHub publishes for the asset (see
        // `InstallTrust`). The other four stay detection-only (`installAssetPattern`
        // nil): MarkText is linker-signed with no sealed resources, so its
        // signature does not verify; ZAP and Wine are unsigned; BlueBubbles carries
        // a Team ID and is a question for the ordinary gate, not this one.

        // Alacritty — ad-hoc signed, no Team ID; one universal dmg per release.
        GitHubReleaseRule(
            bundleID: "org.alacritty",
            owner: "alacritty", repo: "alacritty",
            installAssetPattern: #"^Alacritty-v[0-9.]+\.dmg$"#,
            installerKind: .dmg,
            installTrust: .publishedDigestOnly),
        ])
}
