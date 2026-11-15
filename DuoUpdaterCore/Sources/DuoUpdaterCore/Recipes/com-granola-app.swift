import Foundation

enum com_granola_app {
    // History: docs/app-audits/com-granola-app.md#历史与实测
    static let set = AppRecipeSet(
        family: "com-granola-app",
        probes: [
        // Granola redirects its public manifest to a versioned CloudFront path.
        // Both bundle versions equal `version`; the universal ZIP's exact name
        // and SHA512 belong to that same manifest. Keep the signature/Team gate.
        VendorProbeRecipe(
            bundleID: "com.granola.app",
            url: URL(string: "https://api.granola.ai/v1/check-for-update/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://www.granola.ai/"),
            publishedAtPattern: #"(?m)^releaseDate:\s*'([^']+)'\s*$"#,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dr2v7l5emb758.cloudfront.net/{version}/Granola-{version}-mac-universal.zip"),
                kind: .zip,
                checksumPattern: #"Granola-[^\n]+-mac-universal\.zip\s*\n\s*sha512:\s*([A-Za-z0-9+/=]+)"#)),
        ])
}
