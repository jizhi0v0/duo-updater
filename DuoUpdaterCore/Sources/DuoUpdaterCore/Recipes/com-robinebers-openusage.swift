import Foundation

enum com_robinebers_openusage {
    static let set = AppRecipeSet(
        family: "com-robinebers-openusage",
        changelogPages: [
        // History: docs/app-audits/com-robinebers-openusage.md#历史与实测
        // OpenUsage — resolves through the generic Sparkle source, but not one of
        // its appcast items carries a `<description>` or a
        // `sparkle:releaseNotesLink`, so the app had no notes at all. The vendor
        // writes them on the GitHub releases instead. Web fallback rather than a
        // `ChangelogRecipe`: the release page is the same content the maintainer
        // publishes, and nothing here needs a per-version parse.
        "com.robinebers.openusage": URL(string: "https://github.com/robinebers/openusage/releases")!,
        ])
}
