import Foundation

enum app_cyan_markedit {
    static let set = AppRecipeSet(
        family: "app-cyan-markedit",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.

        // History: docs/app-audits/app-cyan-markedit.md#历史与实测
        // MarkEdit — takes the UNIVERSAL dmg (`MarkEdit-<ver>.dmg`), not the
        // `-apple-silicon` one beside it: the plain dmg is a universal binary
        // (x86_64 + arm64) while `-apple-silicon` is a single arm64 slice. The
        // universal dmg is the better pin: one artifact that runs everywhere, no arch
        // branch.
        // The `[0-9.]+\.dmg$` anchor also keeps `-apple-silicon.dmg` out, and the
        // `UpdateArchive*.zip` payloads are for MarkEdit's own updater, not for us.
        // One-click: app.cyan.markedit, Team TCKG8FBVG6, notarized — verified on the
        // universal dmg.
        GitHubReleaseRule(
            bundleID: "app.cyan.markedit",
            owner: "MarkEdit-app", repo: "MarkEdit",
            installAssetPattern: #"^MarkEdit-[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        ])
}
