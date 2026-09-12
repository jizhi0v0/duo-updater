import Foundation

/// The "have we already told the user about this update?" decision behind the
/// **new updates available** banner, keyed on BOTH halves of the offered version.
///
/// Pulled out of `AppListModel.notifyNewUpdates` so it can be executed: the model
/// itself is not constructible in a test (its `init` registers notification
/// permissions, starts timers and installs FS watchers), and this is the part
/// that can be wrong.
///
/// **Why not the marketing string.** The baseline used to store
/// `remote.displayVersion`, which is `shortVersion ?? version` — a marketing
/// string a vendor is free to leave alone across any number of builds. Amp
/// shipped ten builds called "1.0" on 2026-08-28: the first was announced, the
/// baseline recorded "1.0", and the remaining nine were `isActionableUpdate` —
/// row lit, badge lit — with `wasNotified` permanently true. Quiet becoming
/// silence, the same defect `StagedNudgeLedger` documents itself as avoiding, on
/// a different ledger. `scripts/check_staged_version_use.py` does not see this
/// shape: it hunts `shortVersion ?? buildVersion` spellings, and this one went
/// through a computed property.
public enum NotifiedUpdateVersions {

    /// What to store for an offered update: "1.7.3 (194)", "1.7.3" or "194",
    /// whichever the pair supports. Empty when the offer names no version at all —
    /// which is what the marketing-keyed version stored for those rows too, so an
    /// existing baseline entry keeps matching.
    public static func announceKey(_ offered: VersionSide?) -> String {
        guard let offered, !offered.isEmpty else { return "" }
        return offered.text(withBuild: true)
    }

    /// Whether any of `keys` already holds an announcement for this offer.
    ///
    /// `keys` is plural for the same reason `notifyNewUpdates` consults two: a
    /// baseline written before the switch to per-path keys lives under the old
    /// bundle-id key.
    ///
    /// A stored value equal to the offer's MARKETING half alone also counts as
    /// announced. That is the migration from the marketing-keyed baseline: without
    /// it, the first run after an upgrade re-announces every pending update at
    /// once. It costs at most one PASS per app, not one announcement: the pass
    /// that sees the stale entry rewrites it build-aware, so only builds offered
    /// during that single pass are swallowed — two builds shipped between two
    /// passes are both swallowed, and after it only a genuinely unannounced build
    /// can match. Deliberately not time-limited, because an app that stops being
    /// actionable keeps its old entry indefinitely.
    public static func wasAnnounced(
        _ offered: VersionSide?, under keys: [String], in baseline: [String: String]
    ) -> Bool {
        let key = announceKey(offered)
        let legacyKey = offered?.marketing
        return keys.contains { name in
            guard let stored = baseline[name] else { return false }
            return stored == key || stored == legacyKey
        }
    }
}
