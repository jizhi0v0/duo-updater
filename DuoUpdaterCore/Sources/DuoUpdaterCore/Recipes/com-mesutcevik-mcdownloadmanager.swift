import Foundation

enum com_mesutcevik_mcdownloadmanager {
    static let set = AppRecipeSet(
        family: "com-mesutcevik-mcdownloadmanager",
        githubRules: [
        // MC Download Manager (mstcvk/mc-download-manager, Team D547CSD5CA,
        // notarized from 1.1.0) — no SUFeedURL. Its own `UpdateChecker.swift`
        // reads `/releases/latest`, strips the `v` and offers the dmg as an
        // ordinary download; it never replaces the bundle itself.
        //
        // One track, the release GitHub marks Latest. One universal dmg per
        // release. 1.0.0 is ad-hoc signed (short version `1.0`), so the Team gate
        // refuses one-click for that install; see the audit.
        GitHubReleaseRule(
            bundleID: "com.mesutcevik.mcdownloadmanager",
            owner: "mstcvk", repo: "mc-download-manager",
            versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MC-Download-Manager-[0-9][0-9.]*\.dmg$"#,
            installerKind: .dmg),
        ])
}
