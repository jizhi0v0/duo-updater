import Foundation

enum ai_storyteller_pdfcraft {
    static let set = AppRecipeSet(
        family: "ai-storyteller-pdfcraft",
        githubRules: [
        // Shared rationale for storytold's "-craft" apps: Recipes/ai-storyteller-photocraft.swift.

        // PdfCraft, formerly PrintCraft — the Acrobat counterpart. Same pipeline,
        // same anchors (they keep `-rc.N` tags and the `pdfcraft-cli-…` zip out).
        //
        // From v0.4.0 the repo is storytold/pdfcraft (the old slug only answers
        // through a rename redirect, which costs the request its token), the
        // assets are `pdfcraft-…`, and the app is PdfCraft.app,
        // ai.storyteller.pdfcraft; v0.2.1 and earlier are PrintCraft.app,
        // ai.storyteller.printcraft. Same Team. A PrintCraft copy reaches this
        // rule and its one-click through `BundleIDMigration`; PdfCraft moves the
        // old settings folder over on first launch.
        //
        // The asset pattern takes the new name only: every `printcraft-` dmg is
        // the old id, which gate 4 never lets replace a PdfCraft copy, and none is
        // newer than any PrintCraft copy that could ask.
        // One-click: ai.storyteller.pdfcraft, Team DJ6XS33FX8, notarized.
        GitHubReleaseRule(
            bundleID: "ai.storyteller.pdfcraft",
            owner: "storytold", repo: "pdfcraft",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^pdfcraft-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#,
            installerKind: .dmg),
        ])
}
