import Foundation

enum com_colliderli_iina {
    static let set = AppRecipeSet(
        family: "com-colliderli-iina",
        bindingProofs: [
        ChannelProofKey("com.colliderli.iina", .beta):
            .recipeAnchor(#"appcast-beta\.xml"#, in: ["feedOverride"]),
        ])
}
