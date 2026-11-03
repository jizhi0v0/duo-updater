import Foundation

/// Whether a Setapp update can be kicked off without showing Setapp, and how to
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

    /// Setapp's client, from the two documented install roots.
    public static func clientURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Setapp.app"),
            home.appendingPathComponent("Applications/Setapp.app"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
