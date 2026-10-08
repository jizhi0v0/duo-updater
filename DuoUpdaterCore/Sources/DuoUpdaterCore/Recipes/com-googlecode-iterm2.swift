import Foundation

enum com_googlecode_iterm2 {
    static let set = AppRecipeSet(
        family: "com-googlecode-iterm2",
        bindingProofs: [
        // iTerm2's test-release toggle is a feed swap: stable and testing share
        // host and path prefix and differ only in the filename the bundle
        // declares under `SUFeedURLForTesting`, which is what the anchor targets.
        ChannelProofKey("com.googlecode.iterm2", .beta):
            .recipeAnchor(#"testing_modern\.xml"#, in: ["feedOverride"]),
        ])
}
