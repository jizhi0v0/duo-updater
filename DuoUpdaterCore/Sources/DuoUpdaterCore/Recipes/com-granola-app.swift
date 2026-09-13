import Foundation

enum com_granola_app {
    static let set = AppRecipeSet(
        family: "com-granola-app",
        probes: [
        // Granola — its public latest-mac.yml redirects to a versioned CloudFront
        // manifest. `version` equals both Info.plist version fields. The dmg path is
        // deterministic from that exact resolved version and is universal, so it
        // is safe for one-click. Mounted dmg: com.granola.app, Team QZ7DHHLN25,
        // notarized. The manifest's sha512 is for the zip, not the dmg, so the
        // signature/Team gate is the integrity check for this installer.
        VendorProbeRecipe(
            bundleID: "com.granola.app",
            url: URL(string: "https://api.granola.ai/v1/check-for-update/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.granola.ai/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dr2v7l5emb758.cloudfront.net/{version}/Granola-{version}-mac-universal.dmg"),
                kind: .dmg)),
        ])
}
