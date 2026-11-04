import Foundation

/// Whether a Setapp update can be kicked off without activating Setapp, and how to
/// do it.
///
/// Measured 2026-11-03 in the vmpal VM, both directions:
///
///  - Setapp quit, one managed app relabelled below the catalogue's version,
///    `open -g -a /Applications/Setapp.app` (background, no activation):
///    the app was replaced within 15 s.
///  - Same, with Setapp's own "Install automatically" switched off: nothing
///    happened; the copy stayed at the old version.
///
/// So the client's launch check is the trigger, and the client's setting is the
/// gate. That setting is a per-customer preference with a hashed prefix:
///
///     defaults read com.setapp.DesktopClient
///     "4766321432293575660-ForbiddenAutomaticAppsRefresh" = 1   ← off
///     (key absent)                                              ← on
///
/// The prefix is derived from the account, so it is matched by suffix.
public enum SetappAutomation {

    /// Where the user's own choice is kept — DuoUpdater's preference, not
    /// Setapp's: some people want a background Setapp update (it also updates
    /// every other managed app), some want only the notice.
    public static let backgroundUpdatesPreference = "setappBackgroundUpdates"

    /// The suffix Setapp writes the "do not install automatically" flag under.
    static let forbiddenSuffix = "-ForbiddenAutomaticAppsRefresh"

    /// Setapp's own switch. True means "Install automatically" is off, so a
    /// launch-time check can only tell the user a version exists.
    public static func isAutoRefreshForbidden(
        defaults: UserDefaults? = UserDefaults(suiteName: SetappSubscription.defaultsDomain)
    ) -> Bool {
        guard let defaults else { return false }
        for key in defaults.dictionaryRepresentation().keys where key.hasSuffix(forbiddenSuffix) {
            if let number = defaults.object(forKey: key) as? NSNumber, number.boolValue {
                return true
            }
        }
        return false
    }

    /// A background trigger only makes sense when both sides allow it: the user
    /// asked DuoUpdater to do this, and Setapp will actually install what its
    /// check finds. With Setapp's switch off, the honest offer is to open it.
    public static func canUpdateInBackground(
        userEnabled: Bool,
        defaults: UserDefaults? = UserDefaults(suiteName: SetappSubscription.defaultsDomain)
    ) -> Bool {
        userEnabled && !isAutoRefreshForbidden(defaults: defaults)
    }

    /// Only an actionable Setapp offer can start its installer. The source has
    /// already applied subscription, OS and stable/beta channel checks.
    public static func hasAvailableUpdate(in results: [UpdateResult]) -> Bool {
        !availableUpdates(in: results).isEmpty
    }

    public static func availableUpdates(in results: [UpdateResult]) -> [UpdateResult] {
        results.filter { result in
            guard result.remote?.sourceName == "Setapp",
                  result.remote?.subscriptionHold == nil,
                  case .updateAvailable = result.status else { return false }
            return true
        }
    }

    /// Setapp's launch-time refresh is global: it may install every outdated
    /// managed app, not only the row that made the launch worthwhile. Therefore
    /// one explicitly skipped Setapp version vetoes the whole automatic launch.
    /// The user can still open Setapp manually.
    public static func automaticUpdateCandidates(
        in results: [UpdateResult],
        ignoredApps: [InstalledApp] = [],
        hasStoredSkip: (InstalledApp) -> Bool = { _ in false },
        isVersionSkipped: (UpdateResult) -> Bool
    ) -> [UpdateResult] {
        // Ignored rows intentionally are not checked and therefore carry no
        // remote offer after a refresh. A stored skip on one of those Setapp-owned
        // copies is still an explicit veto: the global client launch could install
        // it as collateral, and without checking the row we cannot prove the
        // skipped release is no longer current.
        guard !ignoredApps.contains(where: {
            SetappCatalogSource.owns($0) && hasStoredSkip($0)
        }) else { return [] }

        let updates = availableUpdates(in: results)
        guard !updates.contains(where: isVersionSkipped) else { return [] }
        return updates
    }

    /// The client's bundle identifier — what `NSRunningApplication` is asked
    /// about before deciding a background launch is worth anything.
    public static let clientBundleIdentifier = "com.setapp.DesktopClient"

    /// Whether a click on the row's Setapp action should launch the client in
    /// the background rather than open the page.
    ///
    /// All three have to agree: the user's preference, the client not already
    /// running (a launch is what runs the check; a running client only gets
    /// activated, and the deep link is lost on that path), and Setapp's own
    /// "Install automatically" switch.
    public static func routesThroughBackground(
        userEnabled: Bool,
        clientRunning: Bool,
        defaults: UserDefaults? = UserDefaults(suiteName: SetappSubscription.defaultsDomain)
    ) -> Bool {
        userEnabled && !clientRunning && !isAutoRefreshForbidden(defaults: defaults)
    }

    /// Setapp's client, from the two documented install roots.
    public static func clientURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Setapp.app"),
            home.appendingPathComponent("Applications/Setapp.app"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
