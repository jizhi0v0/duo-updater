import Foundation

enum com_BlueBubbles_BlueBubbles_Server {
    static let set = AppRecipeSet(
        family: "com-BlueBubbles-BlueBubbles-Server",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/com-BlueBubbles-BlueBubbles-Server.md#历史与实测
        // BlueBubbles server — Developer ID signed (Team WPV275H8W7) but NOT
        // notarized. That does not block the swap: no install gate asks for
        // notarization or a Gatekeeper assessment — `SignatureVerifier.verifyCodeSignature`
        // is `SecStaticCodeCheckValidity` with no requirement, and the gates after it
        // pin Team ID, bundle id, architecture and OS floor. So this is the ordinary
        // Team-ID route (`installTrust` default `.developerID`, which needs no GitHub
        // `digest`), not the detection-only group in `Recipes/org-alacritty.swift`.
        //
        // Best-effort one-click on `BlueBubbles-<ver>-arm64.dmg`, which wraps
        // `BlueBubbles.app` reporting the tag as its version. The bare
        // `BlueBubbles-<ver>.dmg` is an x86_64-only build; DuoUpdater is arm64-only
        // (`App/project.yml`), so the pattern anchors `-arm64` (checked 2026-10-02;
        // History has the measurements). arm64 dmgs exist from v1.9.8 on;
        // `/releases/latest` is what a stable rule reads, so the older single-dmg
        // releases never come into it.
        //
        // The swapped-in build opens without a Gatekeeper prompt — checked end to
        // end once (History has the log): a one-click 1.9.8 → 1.9.9 through the real
        // `InstallCoordinator`, then a first launch. `InPlaceSwap.replace` strips
        // `com.apple.quarantine` before the swap; on that launch `syspolicyd` still
        // ran its notarization lookup (which fails for this build) and an XProtect
        // scan behind a sub-second progress window, then let it run with nothing to
        // click. The Full Disk Access request that follows is BlueBubbles' own — it
        // reads the Messages database — not Gatekeeper's.
        GitHubReleaseRule(
            bundleID: "com.BlueBubbles.BlueBubbles-Server",
            owner: "BlueBubblesApp", repo: "bluebubbles-server",
            installAssetPattern: #"^BlueBubbles-[0-9.]+-arm64\.dmg$"#,
            installerKind: .dmg),
        ])
}
