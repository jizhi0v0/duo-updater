import Foundation

/// The "have we already told the user about this update?" decision behind the
/// **new updates available** banner: app key → the offered versions already
/// announced for it, newest last.
///
/// Pulled out of `AppListModel.notifyNewUpdates` so it can be executed: the model
/// itself is not constructible in a test (its `init` registers notification
/// permissions, starts timers and installs FS watchers), and this is the part
/// that can be wrong.
///
/// **Why not the marketing string.** An entry used to store
/// `remote.displayVersion`, which is `shortVersion ?? version` — a marketing
/// string a vendor is free to leave alone across any number of builds. Amp
/// shipped ten builds called "1.0" on 2026-08-28: the first was announced, the
/// baseline recorded "1.0", and the remaining nine were `isActionableUpdate` —
/// row lit, badge lit — with `wasAnnounced` permanently true. Quiet becoming
/// silence, the same defect `StagedNudgeLedger` documents itself as avoiding, on
/// a different ledger. `scripts/check_staged_version_use.py` does not see this
/// shape: it hunts `shortVersion ?? buildVersion` spellings, and this one went
/// through a computed property.
///
/// **Why a list and not one version.** A vendor endpoint can answer two different
/// versions for the same request, and the historical ledger stored only the last
/// one it saw — so an endpoint alternating between A and B made *every* check
/// read as a brand-new update and post a banner. Measured 2026-09-16 against
/// `center.qoder.sh` (Qoder IDE): 28 polls returned `1.30.1` seventeen times and
/// `1.29.0` eleven, flipping per request, with the local proxy bypassed and a
/// single exit IP — so the machine saw a "new" update every ~6 minutes for hours.
/// `www.dropbox.com/download` does the same at a lower rate (2 of 40 polls named
/// a build that had never appeared in a nightly sweep).
///
/// The obvious fix — refuse to announce a version lower than the one on record —
/// is the one shape that must not be used here, and it was rejected once already
/// on the Release Log ledger (PR #24, 2026-08-21) for the same reason: vendors
/// really do go backwards and stay there. Measured over 117 nightly baselines
/// (`verify/baseline.json`, 38 days, 366 recipes): Dropbox served `268.4.4124`
/// for 228 hours after having offered `270.3.3209`, and ToDesk (`5.1.0.0` →
/// `4.10.1.0`) and BetterDisplay (`5.0.5` → `4.3.7`) went back and have not
/// returned. A high-water mark silences those apps until the vendor climbs past
/// its own withdrawn build — indefinitely, and invisibly. Jump *size* fails the
/// same way: `1.52386.6` → `2.110.0` (Claude) and `4.10.1.0` → `5.0.0.0` (ToDesk)
/// are both real.
///
/// A single observation cannot tell a per-request flap from a genuine multi-day
/// regression — they are the same event, and Dropbox is both — so this ledger
/// deliberately asks neither which one it is nor which way the version moved. It
/// asks only whether this exact string has been announced before. Flap or
/// withdrawal, the repeat is silent; anything genuinely new is announced. A
/// suppressed repeat is *quiet*, not hidden: the row and the Dock badge are
/// driven by `isActionableUpdate`, which never consults this.
public struct NotifiedUpdateVersions: Equatable, Sendable {

    /// How many announced versions an app keeps before the oldest is dropped.
    ///
    /// Measured, not guessed. Replaying the 117 committed baselines through this
    /// ledger, the deepest recurrence is 3 — ToDesk's `4.10.1.0` and Raycast's
    /// `1.104.0` each came back with three other versions seen in between — so 4
    /// is the smallest capacity that re-announces nothing across the whole 38
    /// days (at 1 it re-announces 19 times across 13 apps; at 2 and 3, twice).
    ///
    /// 8 because that measurement can only undercount: those sweeps run every ~6
    /// hours (median gap 5.99h) while the app checks every few minutes, so an
    /// endpoint flipping per request registers there as at most one dip. Dropbox
    /// has named five distinct versions across the history and still answers with
    /// ones the sweeps never recorded. The margin is close to free: the entries are
    /// short strings, so doubling the bound adds a few kilobytes per hundred apps.
    public static let capacity = 8

    public private(set) var entries: [String: [String]]

    public init(_ entries: [String: [String]] = [:]) {
        self.entries = entries.mapValues { Array($0.suffix(Self.capacity)) }
    }

    /// Read the persisted shape, which is a plist dictionary whose values are
    /// arrays now and were bare strings before this ledger grew a list. Both are
    /// accepted for the same reason `wasAnnounced` accepts a marketing-only entry:
    /// discarding the old shape would re-announce every pending update at once on
    /// the first launch after an upgrade.
    public init(persisted: [String: Any]) {
        var value: [String: [String]] = [:]
        for (key, stored) in persisted {
            if let list = stored as? [String] {
                value[key] = Array(list.suffix(Self.capacity))
            } else if let one = stored as? String {
                value[key] = [one]
            }
        }
        self.entries = value
    }

    /// The plist-safe form to persist under the list key.
    public var persistable: [String: [String]] { entries }

    /// The single-version projection an older build reads: app key → the version
    /// most recently announced for it.
    ///
    /// Written alongside `persistable`, to the key this ledger used before it grew
    /// a list, and that redundancy is the point. A build predating the list reads
    /// its key as `[String: String]`, and that cast fails for the WHOLE dictionary
    /// the moment any value is an array — not per entry — so a single downgrade,
    /// or a dev build launched beside the released one on the same preference
    /// domain, would start from an empty ledger and announce every pending update
    /// at once. Keeping the old key accurate means an older build sees exactly
    /// what it saw before, and this one loses nothing: `mergeLastAnnounced` folds
    /// whatever that build recorded back in.
    public var lastAnnounced: [String: String] {
        entries.compactMapValues(\.last)
    }

    /// Fold in the single-version key, for the versions the list does not already
    /// hold.
    ///
    /// Two things write that key: this build (as `lastAnnounced`, where the value
    /// is by construction already the newest element and the merge is a no-op) and
    /// an older build that ran in between, whose announcement the list has never
    /// seen. Only the second case adds anything, and without it that build's
    /// banner would be posted a second time here.
    public mutating func mergeLastAnnounced(_ legacy: [String: Any]) {
        for (key, stored) in legacy {
            guard let version = stored as? String else { continue }
            var list = entries[key] ?? []
            guard !list.contains(version) else { continue }
            list.append(version)
            entries[key] = Array(list.suffix(Self.capacity))
        }
    }

    /// What to store for an offered update: "1.7.3 (194)", "1.7.3" or "194",
    /// whichever the pair supports. Empty when the offer names no version at all —
    /// which is what the marketing-keyed version stored for those rows too, so an
    /// existing entry keeps matching.
    public static func announceKey(_ offered: VersionSide?) -> String {
        guard let offered, !offered.isEmpty else { return "" }
        return offered.text(withBuild: true)
    }

    /// Whether any of `keys` already holds an announcement for this offer.
    ///
    /// `keys` is plural for the same reason `notifyNewUpdates` consults two: an
    /// entry written before the switch to per-path keys lives under the old
    /// bundle-id key.
    ///
    /// A stored value equal to the offer's MARKETING half alone also counts as
    /// announced. That is the migration from the marketing-keyed ledger: without
    /// it, the first run after an upgrade re-announces every pending update at
    /// once. It costs at most one PASS per app, not one announcement: the pass
    /// that sees the stale entry records it build-aware, so only builds offered
    /// during that single pass are swallowed — two builds shipped between two
    /// passes are both swallowed, and after it only a genuinely unannounced build
    /// can match. Deliberately not time-limited, because an app that stops being
    /// actionable keeps its old entry indefinitely.
    public func wasAnnounced(_ offered: VersionSide?, under keys: [String]) -> Bool {
        let key = announceKeyAndLegacy(offered)
        return keys.contains { name in
            guard let stored = entries[name] else { return false }
            return stored.contains(key.exact) || (key.legacy.map(stored.contains) ?? false)
        }
    }

    /// Record an offer as announced under `key`, evicting the least recently seen
    /// entry once the app is over `capacity`.
    ///
    /// Re-recording a version already on the list moves it to the newest end
    /// rather than adding a second copy: an endpoint that keeps naming the same
    /// two versions must not push its own earlier announcements out. That is what
    /// makes the capacity a bound on *distinct* versions in rotation, which is the
    /// quantity the 117 baselines were replayed to size.
    /// Recording also CONSUMES the marketing-only spelling of the same offer, and
    /// that line is load-bearing. `wasAnnounced` accepts a bare "1.0" as covering
    /// "1.0 (2002)" so an upgrade does not re-announce everything once — and while
    /// this ledger held a single version per app, the recording overwrote that
    /// stale spelling, so the leniency expired after one pass. In a list it would
    /// not expire: "1.0" would sit there matching every future build, and Amp's
    /// ten builds called "1.0" would be swallowed again, silently, for as long as
    /// it took `capacity` other versions to evict it. Dropping it here restores
    /// "costs at most one pass". The residual: a vendor that goes back to naming
    /// no build at all re-announces once.
    public mutating func record(_ offered: VersionSide?, under key: String) {
        let version = Self.announceKey(offered)
        var list = entries[key] ?? []
        list.removeAll { $0 == version }
        if let marketing = offered?.marketing, marketing != version {
            list.removeAll { $0 == marketing }
        }
        list.append(version)
        entries[key] = Array(list.suffix(Self.capacity))
    }

    /// Forget apps that are no longer in the scan, so the map cannot grow without
    /// bound across the lifetime of the preference it is persisted in.
    public mutating func prune(liveKeys: Set<String>) {
        entries = entries.filter { liveKeys.contains($0.key) }
    }

    /// The exact string this offer is stored as, plus the marketing-only spelling
    /// an older ledger would have stored for it — nil when they are the same, so
    /// the fallback can never match something the exact key already covers.
    private func announceKeyAndLegacy(_ offered: VersionSide?) -> (exact: String, legacy: String?) {
        let exact = Self.announceKey(offered)
        guard let marketing = offered?.marketing, marketing != exact else { return (exact, nil) }
        return (exact, marketing)
    }
}
