import Foundation

enum com_superultra_kiln {
    static let set = AppRecipeSet(
        family: "com-superultra-kiln",
        probes: [
        // Kiln (Superwhisper's ISO-to-USB tool) — no updater in the app (a Rust
        // binary with no Sparkle and no update address), no repository, no cask.
        // The product page states the version in its server-rendered download
        // line: `<p class="kiln-meta">v<!-- -->0.4.3<!-- --> · …`. The value is a
        // constant in the page's own bundle, next to the download's size, so it
        // moves when the vendor publishes a build.
        //
        // One-click: `latest/Kiln-mac.zip` is an unversioned "latest" URL, the
        // page's only Mac download, holding `Kiln.app` — bundle id
        // com.superultra.kiln, Team XDP69BYUP9, notarized, universal. Short
        // version == build == the page's version.
        VendorProbeRecipe(
            bundleID: "com.superultra.kiln",
            url: URL(string: "https://superwhisper.com/kiln")!,
            mode: .responseBody,
            versionPattern: #"class="kiln-meta">v(?:<!-- -->)?([0-9]+(?:\.[0-9]+)+)<"#,
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://kiln-builds.superwhisper.com/latest/Kiln-mac.zip")!),
                kind: .zip)),
        ])
}
