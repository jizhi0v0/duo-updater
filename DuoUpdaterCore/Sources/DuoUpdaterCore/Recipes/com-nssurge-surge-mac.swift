import Foundation

enum com_nssurge_surge_mac {
    static let set = AppRecipeSet(
        family: "com-nssurge-surge-mac",
        bindingProofs: [
        ChannelProofKey("com.nssurge.surge-mac", .beta):
            .recipeAnchor(#"appcast-signed-beta\.xml"#, in: ["feedOverride"]),
        ],
        changelogPages: [
        // Surge Mac — official release-notes page; the public changelog site is
        // JS-backed, so we point the fallback web view at the vendor page itself.
        "com.nssurge.surge-mac": URL(string: "https://nssurge.com/support/mac/release-notes")!,
        ])
}
