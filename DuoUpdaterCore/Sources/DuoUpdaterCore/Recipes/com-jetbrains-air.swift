import Foundation

enum com_jetbrains_air {
    static let set = AppRecipeSet(
        family: "com-jetbrains-air",
        changelogs: [
        // Air (JetBrains) — the official product-releases API, same endpoint and
        // decoder as IntelliJ IDEA and Toolbox (`Recipes/com-jetbrains-toolbox.swift`).
        // air.dev/changelog is now only a redirect to jetbrains.com/air/ with no
        // release data in it. Each `AIR` element carries `build` (the full
        // "262.834.44" the installed app reports; `version` is only the shared
        // "262.834" train, so the decoder keys AIR entries on `build`) and a
        // `whatsnew` HTML note: an optional `<h4>` headline (the entry title), then
        // `<li>` bullets or `<p>` prose, closed by a "Share your feedback" footer
        // the decoder drops. Air ships only as `preview` today and the endpoint
        // returns nothing for `AIR` without a `type`, so all three types are asked
        // for — a future `release` build still shows up.
        // History: docs/app-audits/com-jetbrains-air.md#历史与实测
        ChangelogRecipe(
            bundleID: "com.jetbrains.air",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=AIR&type=eap,preview,release")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),
        ])
}
