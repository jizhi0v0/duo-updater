import Foundation

/// Which staged relaunches the user has already been told about: app key → the
/// staged version that was announced.
///
/// The rule this encodes is "one banner per staged build, not one per check".
/// The reminder it replaces re-posted every staged build every five minutes for
/// as long as it stayed staged. A stable notification identifier kept
/// Notification Center to a single entry per app, but each repost still alerted
/// — banner and sound — so an app the user was not ready to relaunch nagged
/// twelve times an hour, indefinitely.
///
/// Keying on the *version* rather than the app is what keeps the quiet from
/// becoming silence: a build that sits staged for weeks is announced once, and
/// when the app stages a different build, that is a new pair and it is announced
/// again.
public struct StagedNudgeLedger: Equatable, Sendable {
    public private(set) var entries: [String: String]

    public init(_ entries: [String: String] = [:]) {
        self.entries = entries
    }

    /// Whether this (app, staged version) pair has not been announced yet.
    public func isNew(key: String, version: String) -> Bool {
        entries[key] != version
    }

    /// Record a pair as announced. Replaces any earlier version for the same app:
    /// only the build currently staged can be re-announced against.
    public mutating func record(key: String, version: String) {
        entries[key] = version
    }

    /// Forget one app's entry, so the build it names can be announced again.
    ///
    /// For the case where the user hid the app themselves — ignoring it withdraws
    /// the delivered banner, and the entry has to go with it, or un-ignoring would
    /// restore a row and a badge with nothing in Notification Center to match.
    ///
    /// Not for every banner that gets cleared. An entry is also what stops a
    /// transient reading of the staging area from re-announcing a build the user
    /// has already been told about, so the caller has to be a deliberate, user-made
    /// change of mind rather than a sweep. See `AppListModel.withdrawStagedNudge`,
    /// which is the only caller and says which sites deliberately are not.
    public mutating func forget(key: String) {
        entries[key] = nil
    }

    /// Forget apps that are no longer installed, so the map cannot grow without
    /// bound across the lifetime of the preference it is persisted in.
    ///
    /// Deliberately keyed on "is this app still on the machine", not "is it still
    /// staged": an entry has to outlive the staging it describes. The staged build
    /// disappears at the moment it is applied — which is exactly when a pass that
    /// pruned on staging would forget it, leaving nothing to suppress a repeat if
    /// the same build were seen staged again on a later pass.
    public mutating func prune(liveKeys: Set<String>) {
        entries = entries.filter { liveKeys.contains($0.key) }
    }
}
