import Foundation

/// When Apple usually publishes Xcode: weekdays 09:30–16:00 Pacific.
///
/// Measured 2026-09-23 from Apple's own download list (`dateCreated`, Pacific
/// wall-clock time — see `AppleDeveloperDownloadList.date(from:)`) for the 148
/// Xcode releases since 2020 whose entry was created on the release day: none
/// on a weekend, 65 in the 10:00 hour and 31 in the 09:00 hour; this window
/// holds 86% of them (86% since 2024-09, 24 of 25 in 2026). The afternoon half
/// is not padding: 26.5 beta, 26.5 beta 2, 27 beta 2, 27 beta 3 and 26.6 all
/// came out between 14:00 and 15:40.
public enum XcodeReleaseWindow {
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    static let opensAt = (hour: 9, minute: 30)
    static let closesAt = (hour: 16, minute: 0)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func contains(_ date: Date) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday),  // Monday–Friday
              let hour = parts.hour, let minute = parts.minute
        else { return false }
        let now = hour * 60 + minute
        return now >= opensAt.hour * 60 + opensAt.minute && now < closesAt.hour * 60 + closesAt.minute
    }

    /// The first opening strictly after `date`.
    public static func nextOpening(after date: Date) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            if let opening = calendar.date(
                bySettingHour: opensAt.hour, minute: opensAt.minute, second: 0, of: day),
               opening > date, contains(opening) {
                return opening
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return date.addingTimeInterval(24 * 3600)
    }
}

/// Asks the xcodereleases index every five minutes while `XcodeReleaseWindow` is
/// open, and triggers a normal background check the moment it lists a build it
/// did not list before — rather than at the next scheduled check, which is six
/// hours away by default. Outside the window it asks nothing, except to take
/// its first reading of the index (at most hourly until one succeeds).
///
/// The index is still the only source: it is what the Xcode row, its offer and
/// its install route are built from. It trails Apple by about an hour (median
/// 62 minutes over 14 releases in 2026, 13 minutes to 6½ hours), and this does
/// not shorten that; it removes the wait after it. Each ask is a conditional
/// request — 304 with no body when nothing changed (measured 2026-09-23).
///
/// Apple's release feed (`AppleDeveloperReleaseFeed`) is read in the window too,
/// for one thing: an Xcode build it announced within the last day that the index
/// does not list yet keeps the index asked every five minutes past the window's
/// close, for up to 12 hours — 26.6 was announced for 15:00 PDT and reached the
/// index at 16:13.
///
/// Pure state, so the whole schedule is testable on a simulated clock;
/// `XcodeReleaseWatcher` runs it.
public struct XcodeReleaseWatch: Sendable {
    public static let pollInterval: TimeInterval = 5 * 60
    /// How long an announced build keeps the index asked after the window closes.
    static let pendingLimit: TimeInterval = 12 * 3600
    /// Older announcements are history: the feed keeps ~36 items back months.
    static let announcementFreshness: TimeInterval = 24 * 3600
    /// Outside the window the watch sleeps toward the next opening, but in steps
    /// no longer than this, so a clock or time-zone change is noticed.
    static let longestSleep: TimeInterval = 3600

    /// One index entry, as far as "is it new" goes. Identity is the index's
    /// `_versionOrder` with the build, not the build alone: the last RC and the
    /// GA share a build (27 RC and 27 are both 27A266a) and differ only in order.
    public struct IndexEntry: Sendable, Hashable {
        public let id: String
        public let build: String
        /// "27.0 RC 1 (27A266a)", for the log.
        public let label: String

        public init(order: Int, build: String, label: String) {
            self.id = "\(order) \(build)"
            self.build = build
            self.label = label
        }
    }

    public enum IndexAnswer: Sendable {
        case entries([IndexEntry])
        case failed(String)
    }

    public enum FeedAnswer: Sendable {
        case announcements([AppleDeveloperReleaseFeed.Announcement])
        case failed(String)
    }

    /// What one ask changed, for the log and the tests.
    public enum Event: Sendable, Equatable {
        /// The first readable index this launch: what is already there is not new.
        case baseline(entries: Int)
        case unchanged(entries: Int)
        case newEntries([String])
        /// Unreachable, not a 2xx, or no Xcode entry in it. Nothing is concluded
        /// from it: the builds already seen stay seen, and no check is triggered.
        case indexFailed(String, consecutive: Int)
        case indexRecovered(afterFailures: Int)
        case feedRead(xcodeItems: Int)
        case feedFailed(String, consecutive: Int)
        case feedRecovered(afterFailures: Int)
        case announced(build: String, title: String)
        case pendingListed(build: String)
        case pendingAbandoned(build: String)
    }

    /// Every entry id the index has listed this launch; nil until one readable
    /// answer. Only ever grows, so an index that comes back short (a partial
    /// deploy) and then whole again does not read as a pile of new entries.
    public private(set) var seen: Set<String>?
    private var seenBuilds: Set<String> = []
    /// Announced builds the index does not list yet, and when each was first seen.
    public private(set) var pending: [String: Date] = [:]
    private var abandoned: Set<String> = []
    /// The index gained a build and the check that picks it up has not run.
    public private(set) var checkOwed = false
    private var consecutiveIndexFailures = 0
    private var consecutiveFeedFailures = 0

    public init() {}

    /// Whether to ask anything at `now`. Before the first readable answer the
    /// index is asked at every wake, in the window or not: a baseline first taken
    /// after an outage that hid a release would absorb that release as old.
    public func isActive(at now: Date) -> Bool {
        seen == nil || checkOwed || !pending.isEmpty || XcodeReleaseWindow.contains(now)
    }

    /// Five minutes while there is a reason to ask; otherwise toward the next
    /// opening — which also paces a missing baseline outside the window.
    public func nextWait(from now: Date) -> TimeInterval {
        if checkOwed || !pending.isEmpty || XcodeReleaseWindow.contains(now) { return Self.pollInterval }
        let untilOpening = XcodeReleaseWindow.nextOpening(after: now).timeIntervalSince(now)
        return max(1, min(untilOpening, Self.longestSleep))
    }

    public mutating func absorb(index: IndexAnswer, feed: FeedAnswer?, at now: Date) -> [Event] {
        var events: [Event] = []

        switch index {
        case .entries(let entries) where !entries.isEmpty:
            if consecutiveIndexFailures > 0 {
                events.append(.indexRecovered(afterFailures: consecutiveIndexFailures))
                consecutiveIndexFailures = 0
            }
            let current = Set(entries.map(\.id))
            let builds = Set(entries.map(\.build))
            if let known = seen {
                let added = entries.filter { !known.contains($0.id) }
                seen = known.union(current)
                if added.isEmpty {
                    events.append(.unchanged(entries: current.count))
                } else {
                    events.append(.newEntries(Array(Set(added.map(\.label))).sorted()))
                    checkOwed = true
                }
            } else {
                seen = current
                events.append(.baseline(entries: current.count))
            }
            seenBuilds.formUnion(builds)
            for build in pending.keys.sorted() where builds.contains(build) {
                pending[build] = nil
                events.append(.pendingListed(build: build))
            }
        case .entries:
            consecutiveIndexFailures += 1
            events.append(.indexFailed("no Xcode entries", consecutive: consecutiveIndexFailures))
        case .failed(let reason):
            consecutiveIndexFailures += 1
            events.append(.indexFailed(reason, consecutive: consecutiveIndexFailures))
        }

        switch feed {
        case .announcements(let items)?:
            if consecutiveFeedFailures > 0 {
                events.append(.feedRecovered(afterFailures: consecutiveFeedFailures))
                consecutiveFeedFailures = 0
            }
            events.append(.feedRead(xcodeItems: items.count))
            // Without a readable index there is nothing to compare against; a
            // fresh item is still fresh at the next ask.
            if seen != nil {
                for item in items
                where now.timeIntervalSince(item.date) <= Self.announcementFreshness
                    && !seenBuilds.contains(item.build)
                    && pending[item.build] == nil
                    && !abandoned.contains(item.build) {
                    pending[item.build] = now
                    events.append(.announced(build: item.build, title: item.title))
                }
            }
        case .failed(let reason)?:
            consecutiveFeedFailures += 1
            events.append(.feedFailed(reason, consecutive: consecutiveFeedFailures))
        case nil:
            break
        }

        for (build, since) in pending.sorted(by: { $0.key < $1.key })
        where now.timeIntervalSince(since) >= Self.pendingLimit {
            pending[build] = nil
            abandoned.insert(build)
            events.append(.pendingAbandoned(build: build))
        }
        return events
    }

    /// The owed check ran.
    public mutating func checkRan() {
        checkOwed = false
    }
}

/// Runs `XcodeReleaseWatch` against the world. Everything it touches comes in
/// through `Environment`, so a test can drive the real loop on a simulated
/// clock with scripted answers and failures.
public enum XcodeReleaseWatcher {
    public enum Gate: Sendable, Equatable {
        case on
        /// Not wanted at all right now (no Xcode outside the App Store, checks
        /// already this frequent or manual). No request is made.
        case off(String)
        /// Wanted but no network: skip this ask, keep what is owed.
        case offline
    }

    public struct Environment: Sendable {
        public var now: @Sendable () -> Date
        /// Throws when cancelled, which ends `run`.
        public var sleep: @Sendable (TimeInterval) async throws -> Void
        public var indexEntries: @Sendable () async throws -> [XcodeReleaseWatch.IndexEntry]
        public var announcements: @Sendable () async throws -> [AppleDeveloperReleaseFeed.Announcement]
        public var gate: @Sendable () async -> Gate
        /// Run a normal background check; false when one could not start (a check
        /// or install already running), so it is asked again next time.
        public var check: @Sendable () async -> Bool
        /// A log line; `notable` for the ones worth keeping past the in-memory buffer.
        public var log: @Sendable (_ message: String, _ notable: Bool) -> Void

        public init(
            now: @escaping @Sendable () -> Date,
            sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
            indexEntries: @escaping @Sendable () async throws -> [XcodeReleaseWatch.IndexEntry],
            announcements: @escaping @Sendable () async throws -> [AppleDeveloperReleaseFeed.Announcement],
            gate: @escaping @Sendable () async -> Gate,
            check: @escaping @Sendable () async -> Bool,
            log: @escaping @Sendable (_ message: String, _ notable: Bool) -> Void
        ) {
            self.now = now
            self.sleep = sleep
            self.indexEntries = indexEntries
            self.announcements = announcements
            self.gate = gate
            self.check = check
            self.log = log
        }

        /// The real clock and network; the caller supplies the app's side.
        public static func live(
            gate: @escaping @Sendable () async -> Gate,
            check: @escaping @Sendable () async -> Bool,
            log: @escaping @Sendable (_ message: String, _ notable: Bool) -> Void
        ) -> Environment {
            Environment(
                now: { Date() },
                sleep: { try await Task.sleep(for: .seconds($0)) },
                indexEntries: {
                    try await XcodeReleasesSource().fetch().map {
                        XcodeReleaseWatch.IndexEntry(order: $0.order, build: $0.build, label: $0.displayVersion)
                    }
                },
                announcements: { try await AppleDeveloperReleaseFeed.fetch() },
                gate: gate, check: check, log: log)
        }
    }

    /// Loops until `environment.sleep` throws (cancellation).
    public static func run(_ environment: Environment) async {
        var watch = XcodeReleaseWatch()
        var lastGate: Gate?
        while !Task.isCancelled {
            let now = environment.now()
            if watch.isActive(at: now) {
                let gate = await environment.gate()
                if gate != lastGate {
                    switch gate {
                    case .on: environment.log("xcode watch: on", false)
                    case .off(let why): environment.log("xcode watch: off — \(why)", false)
                    case .offline: environment.log("xcode watch: offline — skipping", false)
                    }
                    lastGate = gate
                }
                if gate == .on {
                    await ask(&watch, at: now, environment)
                }
            }
            do {
                try await environment.sleep(watch.nextWait(from: environment.now()))
            } catch {
                return
            }
        }
    }

    private static func ask(_ watch: inout XcodeReleaseWatch, at now: Date, _ environment: Environment) async {
        let index: XcodeReleaseWatch.IndexAnswer
        do {
            index = .entries(try await environment.indexEntries())
        } catch {
            index = .failed(describe(error))
        }
        var feed: XcodeReleaseWatch.FeedAnswer?
        if XcodeReleaseWindow.contains(now) {
            do {
                feed = .announcements(try await environment.announcements())
            } catch {
                feed = .failed(describe(error))
            }
        }
        for event in watch.absorb(index: index, feed: feed, at: now) {
            let (line, notable) = describe(event)
            environment.log("xcode watch: \(line)", notable)
        }
        if watch.checkOwed {
            if await environment.check() {
                watch.checkRan()
                environment.log("xcode watch: ran a check for the new index entries", true)
            } else {
                environment.log("xcode watch: check owed, busy — asking again in 5 min", true)
            }
        }
    }

    static func describe(_ event: XcodeReleaseWatch.Event) -> (String, Bool) {
        switch event {
        case .baseline(let n): return ("index baseline, \(n) entries", false)
        case .unchanged(let n): return ("index unchanged, \(n) entries", false)
        case .newEntries(let labels): return ("index lists new: \(labels.joined(separator: ", "))", true)
        // An outage is kept once, where it starts and where it ends, not every five minutes.
        case .indexFailed(let why, let n): return ("index unavailable (\(why)), \(n) in a row", n == 1)
        case .indexRecovered(let n): return ("index back after \(n) failed ask(s)", true)
        case .feedRead(let n): return ("Apple feed read, \(n) Xcode item(s)", false)
        case .feedFailed(let why, let n): return ("Apple feed unavailable (\(why)), \(n) in a row", n == 1)
        case .feedRecovered(let n): return ("Apple feed back after \(n) failed ask(s)", true)
        case .announced(_, let title):
            return ("Apple announced \(title), not in the index yet — asking until it is (≤12 h)", true)
        case .pendingListed(let build): return ("index now lists announced \(build)", true)
        case .pendingAbandoned(let build): return ("gave up waiting for the index to list \(build)", true)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let url = error as? URLError { return "URLError \(url.code.rawValue)" }
        return String(describing: error)
    }
}
