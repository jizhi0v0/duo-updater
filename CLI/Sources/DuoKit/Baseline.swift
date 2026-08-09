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
        /// Sweeps since the last comment on the open issue, for the rate limit
        /// that keeps a daily job from producing a daily comment.
        public var sweepsSinceComment = 0
        /// The failure signature the last LLM suggestion was written about, so
        /// a suggestion is posted once per distinct problem rather than every
        /// sweep, and is never shown against a failure it doesn't describe.
        public var triagedSignature: String?

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
            triagedSignature = try c.decodeIfPresent(String.self, forKey: .triagedSignature)
        }
    }

    /// Actionable sweeps below this never produce an issue. One sweep of trouble
    /// is noise; two consecutive sweeps a day apart is a pattern.
    public static let actionableThreshold = 2

    /// Consecutive *unreachable* sweeps before an endpoint is reported as gone.
    ///
    /// Much higher than `actionableThreshold` on purpose. Unreachability is the
    /// one signal that is routinely someone else's fault — a vendor's bad night,
    /// the runner's flaky uplink — so the bar has to be high enough that none of
    /// those clear it. At one sweep a night, five is the better part of a week:
    /// no CDN incident lasts that long, and no DNS record is missing that long
    /// by accident.
    public static let infraThreshold = 5

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
    public func isReportable(_ recipeID: String) -> Bool {
        (entries[recipeID]?.consecutiveActionable ?? 0) >= Self.actionableThreshold
    }

    public func streak(_ recipeID: String) -> Int {
        entries[recipeID]?.consecutiveActionable ?? 0
    }

    /// Whether this recipe's endpoint has been unreachable long enough that the
    /// network is no longer a plausible explanation.
    public func isInfraReportable(_ recipeID: String) -> Bool {
        (entries[recipeID]?.consecutiveInfra ?? 0) >= Self.infraThreshold
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
        guard !warnings.isEmpty else { return "unknown" }
        // Warning text embeds versions that change between sweeps; key on the
        // leading phrase so "still the same problem" stays stable.
        return warnings.map { String($0.prefix(40)) }.sorted().joined(separator: "|")
    }
}
