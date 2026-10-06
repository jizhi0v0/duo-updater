import Foundation

/// A vendor that renamed its app's bundle id between two releases, recorded
/// so a copy still on the old id is checked and updated as the app it is.
///
/// Recipes are keyed by the NEW id, the one the vendor ships today. Two places
/// read this table, and nothing else does:
///  - `InstalledApp.recipeBundleID` files an old-id copy under the new id, so
///    vendor probes and changelog recipes find it. `bundleID` itself stays the
///    id on disk: restart, running-copy and self-updater checks look the
///    process up by it, and an old-id copy runs as the old id.
///  - `SignatureVerifier.verifyBundleIdentifierMatch` lets a download signed as
///    `to` replace a copy signed as `from` — that one direction, only for the
///    registered Team, only for an installed version below `firstToVersion`.
///    The Team-ID gate still runs first, unchanged.
///
/// `firstToVersion` is a bound, not a guess at the exact release that switched:
/// a copy still signed as `from` at or above it is not the rename we measured,
/// so it gets neither the recipes nor the swap. Record the versions as observed
/// on real artifacts and say where in the app's audit doc.
public struct BundleIDMigration: Sendable, Equatable {
    public let from: String
    public let to: String
    /// The Team both ids are signed by. A migration never crosses Teams.
    public let teamID: String
    /// The newest release observed still signed as `from`.
    public let lastFromVersion: String
    /// The oldest release observed signed as `to`.
    public let firstToVersion: String

    public static let all: [BundleIDMigration] = [
        // WorkBuddy, China site: 5.3.14 (2026-08-17) is `com.workbuddy.workbuddy`,
        // 5.5.4 (2026-09-16) and every build since is `com.tencent.workbuddy.mac`;
        // the releases between could not be fetched. The vendor's own updater
        // migrates old copies (its 5.1.0 notes: "macOS Bundle ID 迁移更新器") and
        // the new app carries a helper signed as the old id to unregister the old
        // login item. See docs/app-audits/com-workbuddy-workbuddy.md.
        BundleIDMigration(
            from: "com.workbuddy.workbuddy", to: "com.tencent.workbuddy.mac",
            teamID: "FN2V63AD2J", lastFromVersion: "5.3.14", firstToVersion: "5.5.4"),
    ]

    /// Whether an installed copy signed as `from` at `version` is this rename.
    /// No version, no match: the bound is the whole guard.
    func covers(installedVersion version: String?) -> Bool {
        guard let version else { return false }
        return VersionComparator.compare(version, firstToVersion) == .orderedAscending
    }

    /// The id an installed copy's recipes are filed under: the new id for a
    /// registered old id below its bound, the id itself otherwise.
    public static func recipeBundleID(
        for bundleID: String, installedVersion: String?, in table: [BundleIDMigration] = all
    ) -> String {
        table.first { $0.from == bundleID && $0.covers(installedVersion: installedVersion) }?.to
            ?? bundleID
    }

    /// `bundleID` and every id a registered rename pairs it with, in either
    /// direction. For finding processes by path: right after a swap the bundle
    /// on disk is the new id while the process still running from that path is
    /// the old one. Callers must still filter by path; this only widens the
    /// identifier query.
    public static func relatedBundleIDs(
        of bundleID: String, in table: [BundleIDMigration] = all
    ) -> [String] {
        [bundleID] + table.compactMap {
            $0.from == bundleID ? $0.to : ($0.to == bundleID ? $0.from : nil)
        }
    }

    /// The registered rename that lets a download signed as `downloaded` replace
    /// a copy signed as `installed`, or nil. Both Teams must be the entry's.
    public static func migration(
        installed: String, downloaded: String, installedVersion: String?,
        installedTeam: String?, downloadedTeam: String?, in table: [BundleIDMigration] = all
    ) -> BundleIDMigration? {
        table.first {
            $0.from == installed && $0.to == downloaded
                && installedTeam == $0.teamID && downloadedTeam == $0.teamID
                && $0.covers(installedVersion: installedVersion)
        }
    }
}
