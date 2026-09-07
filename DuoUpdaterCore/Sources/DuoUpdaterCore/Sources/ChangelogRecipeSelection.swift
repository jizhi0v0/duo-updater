import Foundation

/// Select vendor notes using the installed copy's provenance, even when an
/// update lookup has not answered or has failed.
public enum ChangelogRecipeSelection {
    public static func recipe(for result: UpdateResult) -> ChangelogRecipe? {
        guard !result.app.isMASApp, result.remote?.appStore == nil else { return nil }
        return ChangelogRecipeRegistry.recipe(
            forBundleID: result.app.bundleID, channel: result.effectiveReleaseChannel,
            version: targetVersion(for: result))
    }

    /// Lookup, fetching and caching must all use the same version window.
    public static func targetVersion(for result: UpdateResult) -> String? {
        result.remote?.displayVersion ?? result.app.shortVersion
    }
}
