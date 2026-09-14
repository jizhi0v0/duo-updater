import Foundation

enum com_jetbrains_toolbox {
    static let set = AppRecipeSet(
        family: "com-jetbrains-toolbox",
        probes: [
        // JetBrains Toolbox — uses the 4-component `build`, which matches the
        // app's CFBundleShortVersionString (e.g. 3.4.3.81140). The same releases
        // JSON carries the aarch64 dmg under `downloads.macM1`, so we install in
        // place — same shape as the IntelliJ recipes (`Recipes/com-jetbrains-intellij.swift`). No inline sha256 (the
        // API gives only a `checksumLink`), so we lean on the mandatory Team ID
        // gate: the dmg is notarized under 2ZEFAR8TH3 (JetBrains s.r.o.). The
        // `[^}]*?` lazily skips within the `macM1` object to its `link`; `macM1`'s
        // link is the arm64 build, so no `-arm64` anchor is needed here. Apple
        // Silicon only. (Toolbox self-updates, but this is a best-effort one-click
        // with the Team gate as backstop — it never force-kills; a running Toolbox
        // is quit and relaunched by VendorInstaller like any other in-place dmg.)
        VendorProbeRecipe(
            bundleID: "com.jetbrains.toolbox",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://blog.jetbrains.com/toolbox-app/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // JetBrains Toolbox App — JetBrains publishes no public changelog page
        // (long-requested: YouTrack TBX-2807), but the official product-releases
        // API the download site itself uses returns the full history as JSON. The
        // `TBA` product code is the Toolbox App; each element of the TBA array has
        // `version` (e.g. "3.7.2"), `date`, and a `whatsnew` HTML string. Structured
        // decode, same reason and same decoder as IntelliJ IDEA (`Recipes/com-jetbrains-intellij.swift`; shared
        // endpoint shape, JSON-escaped HTML the regex path used to scrape as text).
        // Toolbox's `whatsnew` is CUMULATIVE — each release concatenates its own
        // `<li>` bullets with the full prior minor release's `<h3>`/`<h4>` + `<p>`
        // write-up — so the decoder sweeps BOTH `<li>` and `<p>` (the decoder
        // branches on the response's own top-level key, "TBA" vs "IIU") and drops
        // only the trailing "See the full list of release notes…" `<p>` footer.
        ChangelogRecipe(
            bundleID: "com.jetbrains.toolbox",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),
        ])
}
