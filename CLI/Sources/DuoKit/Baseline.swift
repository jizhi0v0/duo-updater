import Foundation
import DuoUpdaterCore

/// The verifier's memory between runs, checked into the repo at
/// `verify/baseline.json`.
///
/// One file doing three jobs, deliberately:
///
///  1. **Monotonicity baseline** — the last version each recipe successfully
///     read. A recipe that goes *backwards* has almost certainly started
///     matching something else on the page; nothing else detects that.
///  2. **Flap suppressor** — `consecutiveActionable`, so a single bad sweep
///     never files anything. Vendors have five-minute outages; issues are
///     forever.
///  3. **Issue de-dupe** — the issue number opened for each recipe, so
///     reconciliation never has to search GitHub and can never open a duplicate.
///
/// Keeping them together is what lets the whole reconcile step be a pure
/// function of (this file, this run's findings).
public struct Baseline: Codable, Sendable {
    public var schemaVersion = 1
    public var updatedAt: Date = .init()
    public var entries: [String: Entry] = [:]

    public struct Entry: Codable, Sendable {
        public var lastGoodVersion: String?
        public var lastGoodAt: Date?
        /// Consecutive sweeps in which this recipe was broken *or* degraded.
        /// Warnings count: `installURLUnresolved` is how both of the real
        /// one-click failures were found, and neither ever produced a `broken`.
        public var consecutiveActionable = 0
        /// Consecutive sweeps in which the endpoint could not be reached at all.
        ///
        /// Tracked separately from `consecutiveActionable` because the two mean
        /// opposite things about urgency: one bad *parse* is suspicious
        /// immediately, one bad *connection* is almost always the network. But a
        /// connection that fails every night for a week is not the network — it
        /// is a host that no longer exists, and that is exactly as fatal to a
        /// recipe as a pattern that stopped matching.
        public var consecutiveInfra = 0
        /// When the current unreachable run began. Carried into the issue because
        /// "unreachable since 2026-08-04" is the fact that settles whether a host
        /// is having a bad week or has been retired.
        public var infraSince: Date?
        /// What was wrong last time — a failure kind, or the set of warnings.
        /// A *change* in this is new information and worth speaking up about
        /// immediately, where a repeat is not.
        public var lastSignature: String?
        /// Set by the reconcile step, read by it on the next run.
        public var issueNumber: Int?
        public var closedAt: Date?
        /// Sweeps since the last comment on the open issue. Kept for the issue
        /// text ("still down, N sweeps"); the rate limit itself is `lastCommentedAt`.
        public var sweepsSinceComment = 0
        /// When the installer URL first started failing for a reason we call
        /// transient, and how many sweeps have seen it.
        ///
        /// A vendor 5xx on the install URL is deliberately not actionable — that
        /// was the whole point of splitting it out of `installURLUnresolved`. But
        /// "not actionable" was implemented as "never actionable", which recreated
        /// the exact silent failure this sweep exists to end: an install URL that
        /// 5xxs forever reported `.ok` on every run and could never be seen. It is
        /// transient only for as long as it is brief; past that it is a dead
        /// endpoint wearing a 5xx, and it ages into a report the same way
        /// unreachability does.
        public var installTransientSince: Date?
        public var consecutiveInstallTransient = 0
        /// When the open issue was last commented on, for the nudge rate limit.
        /// A timestamp rather than a sweep count for the same reason as
        /// `infraSince`: the interval is meant to be a week of wall-clock, and a
        /// count only says that as long as the cadence never moves.
        public var lastCommentedAt: Date?
        /// The failure signature the last LLM suggestion was written about, so
        /// a suggestion is posted once per distinct problem rather than every
        /// sweep, and is never shown against a failure it doesn't describe.
        public var triagedSignature: String?

        /// Whether this endpoint has been unreachable long enough, and often
        /// enough, that the network has stopped being a plausible explanation.
        ///
        /// Both conditions are load-bearing: see `Baseline.infraWindow` for why
        /// the wall-clock one replaced a sweep count, and
        /// `Baseline.minInfraObservations` for why a count still has to be there.
        public func isInfraReportable(now: Date = Date()) -> Bool {
            guard consecutiveInfra >= Baseline.minInfraObservations,
                  let elapsed = infraElapsed(now: now) else { return false }
            return elapsed >= Baseline.infraWindow
        }

        /// Whether the open issue may be nudged again yet. An issue that has never
        /// been commented on is always eligible.
        public func mayComment(now: Date = Date()) -> Bool {
            guard let lastCommentedAt else { return true }
            return now.timeIntervalSince(lastCommentedAt) >= Baseline.commentInterval
        }

        /// Whether the installer URL has been failing transiently for long enough,
        /// and often enough, that "the vendor is having a bad minute" has stopped
        /// being a credible explanation. Same window and same floor as
        /// `isInfraReportable`, for the same reason.
        public func isInstallTransientReportable(now: Date = Date()) -> Bool {
            guard consecutiveInstallTransient >= Baseline.minInfraObservations,
                  let since = installTransientSince else { return false }
            return now.timeIntervalSince(since) >= Baseline.infraWindow
        }

        /// How long since the open issue was last nudged, or nil if never.
        public func sinceLastComment(now: Date = Date()) -> TimeInterval? {
            lastCommentedAt.map { now.timeIntervalSince($0) }
        }

        /// How long the current unreachable run has been going, or nil when the
        /// endpoint is not currently in one.
        public func infraElapsed(now: Date = Date()) -> TimeInterval? {
            guard let infraSince else { return nil }
            return now.timeIntervalSince(infraSince)
        }

        public init() {}

        /// Deliberately forgiving: every field defaults, so adding or renaming
        /// one doesn't make the whole file unreadable.
        ///
        /// This matters more than it looks. Swift's synthesized decoder ignores
        /// property defaults and throws on a missing key, `load` falls back to an
        /// empty baseline on any decode error, and an empty baseline means every
        /// issue number is forgotten — so the next run reopens a duplicate of
        /// every issue that is already open. One renamed field would do it.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lastGoodVersion = try c.decodeIfPresent(String.self, forKey: .lastGoodVersion)
            lastGoodAt = try c.decodeIfPresent(Date.self, forKey: .lastGoodAt)
            consecutiveActionable =
                try c.decodeIfPresent(Int.self, forKey: .consecutiveActionable) ?? 0
            consecutiveInfra = try c.decodeIfPresent(Int.self, forKey: .consecutiveInfra) ?? 0
            infraSince = try c.decodeIfPresent(Date.self, forKey: .infraSince)
            lastSignature = try c.decodeIfPresent(String.self, forKey: .lastSignature)
            issueNumber = try c.decodeIfPresent(Int.self, forKey: .issueNumber)
            closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
            sweepsSinceComment =
                try c.decodeIfPresent(Int.self, forKey: .sweepsSinceComment) ?? 0
            installTransientSince =
                try c.decodeIfPresent(Date.self, forKey: .installTransientSince)
            consecutiveInstallTransient =
                try c.decodeIfPresent(Int.self, forKey: .consecutiveInstallTransient) ?? 0
            lastCommentedAt = try c.decodeIfPresent(Date.self, forKey: .lastCommentedAt)
            triagedSignature = try c.decodeIfPresent(String.self, forKey: .triagedSignature)
        }
    }

    /// Actionable sweeps below this never produce an issue. One sweep of trouble
    /// is noise; two consecutive sweeps is a pattern.
    ///
    /// Left at two when the sweep moved from nightly to every six hours, which
    /// tightens the wait from two days to twelve hours. That is the point of the
    /// change — a broken recipe is invisible until a sweep reports it — and it
    /// stays safe because the noisy failures it could otherwise catch (a vendor's
    /// maintenance window returning 5xx or 429) are classified `.infra`, not
    /// actionable, and are gated separately below.
    public static let actionableThreshold = 2

    /// Consecutive *unreachable* sweeps before an endpoint is reported as gone.
    ///
    /// Much higher than `actionableThreshold` on purpose. Unreachability is the
    /// one signal that is routinely someone else's fault — a vendor's bad night,
    /// the runner's flaky uplink — so the bar has to be high enough that none of
    /// those clear it.
    ///
    /// Expressed as wall-clock rather than a sweep count, because wall-clock is
    /// the property that actually matters: no CDN incident lasts five days and no
    /// DNS record is missing that long by accident. Counting sweeps encoded the
    /// same intent only as long as the cadence never moved — and when it did move
    /// (nightly to six-hourly) the constant silently came to mean thirty hours,
    /// which a long outage clears. Two separate constants had to be rescaled by
    /// hand to fix that. This one cannot drift.
    public static let infraWindow: TimeInterval = 5 * 24 * 60 * 60

    /// How many unreachable sweeps must actually have been observed, on top of
    /// `infraWindow` having elapsed.
    ///
    /// Time alone is not enough in the one case where the sweep itself is what
    /// stopped: if the runner is off for a week, the first sweep back records an
    /// `infraSince` and the second, minutes later, would satisfy any elapsed-time
    /// test on a timestamp that is now days old — reporting a host as retired on
    /// the strength of two observations. Requiring a handful of sweeps as well
    /// keeps that honest without reintroducing the cadence coupling: at any
    /// sensible interval the window is the binding constraint, and this only
    /// takes over when sweeps are sparse.
    public static let minInfraObservations = 3

    /// How long to wait before nudging an issue that is still open and still
    /// saying the same thing. A job that comments every run is a notification
    /// that says nothing new.
    ///
    /// Wall-clock for the same reason as `infraWindow`: this was seven sweeps,
    /// which meant a week nightly and under two days once the sweep moved to
    /// six-hourly. Both constants had to be rescaled by hand for that one change;
    /// neither can drift now.
    public static let commentInterval: TimeInterval = 7 * 24 * 60 * 60

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        entries = try c.decodeIfPresent([String: Entry].self, forKey: .entries) ?? [:]
    }

    public static func load(from url: URL) -> Baseline {
        guard let data = try? Data(contentsOf: url) else { return Baseline() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Baseline.self, from: data)
        } catch {
            // Losing the baseline means losing every issue number, which means
            // duplicating every open issue on the next run. Say so loudly rather
            // than starting over in silence.
            FileHandle.standardError.write(Data("""
                ⚠︎ could not read the baseline at \(url.path): \(error)
                  Continuing with no history — this run may reopen issues that are
                  already open. Restore the file from git before the next sweep.\n
                """.utf8))
            return Baseline()
        }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Compare this run against what we knew, returning the complaint to attach
    /// (if any) — then fold the run into the baseline.
    ///
    /// The version-regression check lives here because it is the only check that
    /// needs history: the answer looks perfectly well-formed in isolation, and
    /// only "we read 4.7.9 yesterday and 4.7 today" reveals that the pattern
    /// started matching a shorter, different thing.
    @discardableResult
    public mutating func reconcile(_ finding: Finding) -> String? {
        var entry = entries[finding.recipeID] ?? Entry()
        var complaint: String?

        if let version = finding.version, finding.status != .infra {
            if let previous = entry.lastGoodVersion, previous != version,
               VersionComparator.isNewer(previous, than: version) {
                complaint = "version went BACKWARDS since the last sweep "
                    + "(\(previous) → \(version)) — the pattern may have started "
                    + "matching a different element"
            }
            entry.lastGoodVersion = version
            entry.lastGoodAt = Date()
        }

        // The installer URL's transient run is tracked on every status, because the
        // finding it rides on stays `.ok` — there is no other place it would age.
        if finding.warnings.contains(ProbeWarning.installURLTransient(status: nil).kind) {
            entry.consecutiveInstallTransient += 1
            if entry.installTransientSince == nil { entry.installTransientSince = Date() }
        } else if finding.status != .skipped {
            // A sweep that resolved the URL, or failed for a different reason,
            // ends the run. `skipped` proves nothing either way.
            entry.consecutiveInstallTransient = 0
            entry.installTransientSince = nil
        }

        // Any status other than `infra` means we got an answer out of the host,
        // which is proof it is still there — whatever else is wrong with the
        // recipe. Only `skipped` proves nothing, because we never looked.
        if finding.status != .infra, finding.status != .skipped {
            entry.consecutiveInfra = 0
            entry.infraSince = nil
        }

        switch finding.status {
        case .ok:
            entry.consecutiveActionable = 0
            entry.lastSignature = nil
            entry.sweepsSinceComment = 0
            entry.lastCommentedAt = nil

        case .broken, .warn:
            entry.consecutiveActionable += 1
            entry.lastSignature = finding.signature
            entry.sweepsSinceComment += 1

        case .infra:
            // `consecutiveActionable` is deliberately untouched in BOTH
            // directions: an unreachable host must not push a recipe over the
            // parse-failure threshold, and must not reset a real streak that is
            // still running — the latter would make a genuinely broken recipe
            // unreportable forever on a flaky network.
            //
            // What is new is that unreachability now accumulates on its own
            // counter. Before this, a host that was retired outright — the
            // vendor deletes the DNS record — produced `infra` on every sweep
            // forever and changed no state at all, so the sweep built to end
            // silent degradation was itself silent about the most total
            // degradation there is.
            entry.consecutiveInfra += 1
            if entry.infraSince == nil { entry.infraSince = Date() }
            // Counted so the every-Nth-sweep comment limit still applies while a
            // host is down. `lastSignature` is left alone on purpose: it belongs
            // to the actionable streak, and overwriting it with a transport error
            // would make the next real failure look like it "changed shape".
            entry.sweepsSinceComment += 1

        case .skipped:
            // We didn't look. Nothing learned, nothing recorded.
            break
        }

        entries[finding.recipeID] = entry
        return complaint
    }

    /// Whether this recipe has been actionable often enough to be worth
    /// reporting.
    /// Drop rows whose recipe no longer exists in any registry.
    ///
    /// The file only ever grew: `reconcile` writes `entries[finding.recipeID]`
    /// and nothing removes. A recipe that is deleted, renamed, or re-keyed
    /// therefore leaves its last state behind forever, and that state reads as a
    /// live signal — `changelog:com.TablePro:-` sat at `consecutiveActionable: 1`
    /// for nine days after its recipe was deliberately removed, looking exactly
    /// like an unattended finding. Re-keying is the common case, not deletion:
    /// Claude Desktop's recipe split into `:ga` + `:rollout`, Zed's changelog
    /// recipes gained a `channel:`, and three GitHub slugs were repointed at
    /// renamed repos — seven stale rows on 2026-08-30, none of them a real
    /// problem and all of them looking like one.
    ///
    /// Two guards, both load-bearing:
    ///
    /// - **An empty `live` prunes nothing.** The caller builds that set from the
    ///   registries; if it ever hands over an empty one, the bug must not be a
    ///   wiped baseline.
    /// - **A row with an OPEN issue stays**, even when orphaned. The issue number
    ///   is the only handle reconciliation has, and issues close on a clean
    ///   verify — which a removed recipe never produces again. Dropping the row
    ///   would strand an issue nothing can close. Kept rows are returned to the
    ///   caller separately so a human can see them.
    ///
    /// Returns the ids removed, and the orphaned ids kept for an open issue.
    @discardableResult
    public mutating func prune(
        keeping live: Set<String>
    ) -> (removed: [String], keptWithOpenIssue: [String]) {
        guard !live.isEmpty else { return ([], []) }
        var removed: [String] = []
        var kept: [String] = []
        for (id, entry) in entries where !live.contains(id) {
            if entry.issueNumber != nil, entry.closedAt == nil {
                kept.append(id)
            } else {
                entries.removeValue(forKey: id)
                removed.append(id)
            }
        }
        return (removed.sorted(), kept.sorted())
    }

    public func isReportable(_ recipeID: String) -> Bool {
        (entries[recipeID]?.consecutiveActionable ?? 0) >= Self.actionableThreshold
    }

    public func streak(_ recipeID: String) -> Int {
        entries[recipeID]?.consecutiveActionable ?? 0
    }

    /// Whether this recipe's endpoint has been unreachable long enough that the
    /// network is no longer a plausible explanation.
    public func isInfraReportable(_ recipeID: String, now: Date = Date()) -> Bool {
        entries[recipeID]?.isInfraReportable(now: now) ?? false
    }

    /// How long the current unreachable run has been going, for display.
    public func infraElapsed(_ recipeID: String, now: Date = Date()) -> TimeInterval? {
        entries[recipeID]?.infraElapsed(now: now)
    }

    public func infraStreak(_ recipeID: String) -> Int {
        entries[recipeID]?.consecutiveInfra ?? 0
    }
}

public extension Finding {
    /// A stable description of *what* is wrong, so the reconcile step can tell a
    /// recipe that is still broken the same way from one that broke differently.
    var signature: String {
        if let failureKind { return failureKind }
        // `installURLTransient` is excluded for the same reason `Verify` excludes
        // it from `actionable`: it accuses nobody. It is also inherently flappy —
        // any CDN 5xx, any timeout — and since the sweep began probing all 129
        // install URLs rather than only the 26 redirect ones, it flaps on 5x as
        // many recipes. Left in, a recipe that already has an open issue for some
        // OTHER warning would flip its signature in and out every sweep, and
        // `Reconcile` returns `.comment` on a changed signature BEFORE it reaches
        // the `mayComment` weekly rate limit — so it would post a "the failure
        // changed shape" comment nightly, forever.
        let stable = publicWarnings.filter {
            !$0.hasPrefix(ProbeWarning.installURLTransient(status: nil).kind)
        }
        guard !stable.isEmpty else { return "unknown" }
        // Warning text embeds versions that change between sweeps; key on the
        // leading phrase so "still the same problem" stays stable.
        return stable.map { String($0.prefix(40)) }.sorted().joined(separator: "|")
    }
}
