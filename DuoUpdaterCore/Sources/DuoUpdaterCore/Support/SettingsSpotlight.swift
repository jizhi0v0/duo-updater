import Foundation

/// A "this setting is new" marker: one blue dot, shown once, for a preference
/// that appeared in a particular release.
///
/// A new setting that lands in the middle of a Settings window nobody reopens is
/// a setting nobody finds. The dot is the smallest thing that fixes that — but it
/// is only honest if it means "new **to you**", which is why this carries the
/// version it shipped in rather than a bare "unseen" flag: a user installing Duo
/// Updater for the first time must not be greeted with dots on features that are
/// simply part of the app they just met.
public struct SettingsSpotlight: Sendable, Hashable, Identifiable {
    /// Stable identifier, persisted once acknowledged. Never reuse one for a
    /// different setting — an old install would count it as already seen.
    public let id: String
    /// The marketing version this setting first shipped in.
    public let introducedIn: String

    public init(id: String, introducedIn: String) {
        self.id = id
        self.introducedIn = introducedIn
    }
}

/// Decides which spotlights are still owed to this user.
///
/// Pure, and deliberately not in the app target: the "who is this user" question
/// has four answers and only one of them shows a dot, which is exactly the kind of
/// judgment that needs tests rather than a plausible-looking `if` inside a view.
public enum SettingsSpotlightLedger {

    /// - Parameters:
    ///   - catalog: every spotlight the running build knows about.
    ///   - currentVersion: this build's marketing version.
    ///   - previousVersion: the marketing version that ran last, nil if we never
    ///     recorded one (either a fresh install, or an upgrade from a build that
    ///     predates this ledger).
    ///   - hasPriorHistory: whether this install has any state at all from before
    ///     — the only way to tell those two nil cases apart. An existing user who
    ///     upgrades into the first build with a ledger should still be told what is
    ///     new; a brand-new user should not.
    ///   - acknowledged: ids already shown and dismissed.
    public static func pending(
        catalog: [SettingsSpotlight],
        currentVersion: String,
        previousVersion: String?,
        hasPriorHistory: Bool,
        acknowledged: Set<String>
    ) -> Set<String> {
        // Never announce something this build does not actually have yet: a
        // spotlight whose version is ahead of the running one would light up a
        // control that isn't there. (Downgrades put a user in exactly this state.)
        let available = catalog.filter { !VersionComparator.isNewer($0.introducedIn, than: currentVersion) }

        guard let previousVersion else {
            // Fresh install: nothing here is new to them.
            guard hasPriorHistory else { return [] }
            // Upgraded from a build with no ledger — everything is new to them
            // except what they somehow already acknowledged.
            return Set(available.map(\.id)).subtracting(acknowledged)
        }

        return Set(
            available
                .filter { VersionComparator.isNewer($0.introducedIn, than: previousVersion) }
                .map(\.id)
        ).subtracting(acknowledged)
    }
}
