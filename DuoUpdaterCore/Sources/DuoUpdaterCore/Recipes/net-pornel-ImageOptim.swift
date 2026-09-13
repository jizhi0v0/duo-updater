import Foundation

enum net_pornel_ImageOptim {
    static let set = AppRecipeSet(
        family: "net-pornel-ImageOptim",
        probes: [
        // ImageOptim — Sparkle appcast carrying only the latest release
        // (descending, single item). Version in sparkle:shortVersionString.
        //
        // DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender above.
        // Measured on the real 1.9.3 bundle (2026-08-31): it declares
        // `SUFeedURL = https://imageoptim.com/appcast.xml`, this exact address, so
        // Sparkle answers first and this row only keeps the endpoint in the sweep.
        VendorProbeRecipe(
            bundleID: "net.pornel.ImageOptim",
            url: URL(string: "https://imageoptim.com/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString="([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://imageoptim.com/changelog.html")!,
            // One-click verified 2026-08-09 on 1.9.3: `ImageOptim.app` in the
            // archive, bundle id net.pornel.ImageOptim, Team 59KZTZA4XR, accepted by
            // spctl. The enclosure is a `.tar.xz`, which `.tarGz` handles despite the
            // name — `VendorInstaller` renames by kind and `ArchiveExtractor` runs
            // `tar -xf` with no compression flag, so tar sniffs xz itself (checked by
            // extracting a deliberately misnamed copy).
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://imageoptim\.com/[^"]+\.tar\.xz)""#),
                kind: .tarGz)),
        ])
}
