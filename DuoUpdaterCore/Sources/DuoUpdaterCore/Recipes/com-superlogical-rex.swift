import Foundation

enum com_superlogical_rex {
    static let set = AppRecipeSet(
        family: "com-superlogical-rex",
        bindingProofs: [
            ChannelProofKey(RexChannel.bundleID, .preview):
                .recipeAnchor(#"\Ahttps://blob\.superlogical\.com/public/rex-app/preview-arm64/appcast\.xml\z"#,
                              in: ["feedOverride"]),
            ChannelProofKey(RexChannel.bundleID, .nightly):
                .recipeAnchor(#"\Ahttps://blob\.superlogical\.com/public/rex-app/snapshot-arm64/appcast\.xml\z"#,
                              in: ["feedOverride"]),
        ])
}
