import Foundation

enum com_objective_see_blockblock_helper {
    static let bundleID = "com.objective-see.blockblock.helper"
    private static let productPage = URL(string: "https://objective-see.org/products/blockblock.html")!

    static let set = AppRecipeSet(
        family: "com-objective-see-blockblock-helper",
        // History: docs/app-audits/com-objective-see-blockblock-helper.md#历史与实测
        // The product page publishes one release's version, ZIP and SHA-256 in
        // its download panel. The vendor installer updates both the scanned
        // menu-bar helper and the Endpoint Security app in /Library.
        probes: [
            VendorProbeRecipe(
                bundleID: bundleID, url: productPage, mode: .responseBody,
                versionPattern: #"<span class="product-meta">\s*v([0-9]+(?:\.[0-9]+)+)\s*·"#,
                downloadURL: productPage,
                entryStartPattern: #"<div class="product-hero">"#,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(
                        #"window\.location\.href='(https://github\.com/objective-see/BlockBlock/releases/download/v[0-9.]+/BlockBlock_[0-9.]+\.zip)';"#),
                    kind: .zip,
                    checksumPattern: #"<code class="sha-popover-hash">([a-fA-F0-9]{64})</code>"#,
                    checksumFormat: .sha256Hex,
                    installerApp: VendorInstallerApp(
                        bundleIdentifier: "com.objective-see.blockblock.installer",
                        teamIdentifier: "VBG97UB4TA",
                        installedPath: "/Applications/BlockBlock Helper.app"))),
        ])
}
