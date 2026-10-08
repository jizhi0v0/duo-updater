import Foundation

/// `brew update` on DuoUpdater's background schedule, so the outdated list the
/// Brew surface reads is not stuck on whatever the taps knew the last time the
/// user happened to run brew.
///
/// Every read of that list is `HOMEBREW_NO_AUTO_UPDATE=1` (`BrewFormulaService`):
/// local tap state, never a fetch. Homebrew's own auto-update is not a daemon
/// either — it runs only before some commands (install, upgrade, tap), at most
/// every `HOMEBREW_AUTO_UPDATE_SECS` (`man brew`, Homebrew 7.0.8, checked
/// 2026-10-08) — so without this a tap can stay stale for as long as the user
/// runs none of them.
///
/// The user's Homebrew settings decide, as they decide for brew itself: never
/// with `HOMEBREW_NO_AUTO_UPDATE` set, and at most once per
/// `HOMEBREW_AUTO_UPDATE_SECS`, or once a day when that is unset (brew's own
/// default is 86400). Both are read from `brew config` under the variables the
/// user's login shell exports — the reads `HomebrewSelfUpdateCheck` makes — and
/// the run gets those variables too. Unreadable means not run: a `brew update`
/// is not a guess to make about what the user turned off.
///
/// When it last ran is persisted (`lastRunKey`), so a relaunch does not run it
/// again. Recorded when it starts, not when it succeeds: a run that fails — a
/// broken remote, a tap that will not fetch — is retried a period later, not on
/// every tick.
public actor HomebrewBackgroundUpdate {

    /// What one tick did.
    public enum Outcome: Equatable, Sendable {
        /// The app's schedule is "Only when I check".
        case manual
        /// Ran less than the period ago.
        case notDue
        /// `HOMEBREW_NO_AUTO_UPDATE` is set.
        case disabled
        /// The login shell's variables or `brew config` could not be read.
        case unreadable
        /// One of DuoUpdater's own brew runs is under way; asked again next tick.
        case busy
        case updated
        case failed(String)
    }

    /// The UserDefaults key the last run is kept under.
    public static let lastRunKey = "HomebrewBackgroundUpdateLastRun"
    /// Without `HOMEBREW_AUTO_UPDATE_SECS`: once a day, brew's own default.
    public static let defaultPeriod: TimeInterval = 24 * 60 * 60
    /// How long one read of the user's settings is trusted. Reading them runs the
    /// login shell (`-l -i`, every rc file) and `brew config`, about a second
    /// together: at the 5-minute schedule that was 288 shells a day for an answer
    /// that changes when the user edits a dotfile.
    static let settingsTTL: TimeInterval = 60 * 60

    /// The seams, so a test runs no shell, no brew and no UserDefaults.
    public struct Seams: Sendable {
        /// The user's shell-exported `HOMEBREW_*` (`LoginShellEnvironment`); nil
        /// when unreadable.
        public var environment: @Sendable () async -> [String: String]?
        /// `brew config` under those variables; nil when unreadable.
        public var config: @Sendable ([String: String]) async -> HomebrewConfig?
        /// Whether none of DuoUpdater's own brew runs is under way, asked right
        /// before running: brew takes one global lock.
        public var idle: @Sendable () async -> Bool
        /// Run `brew update` with those variables.
        public var update: @Sendable ([String: String]) async throws -> Void
        public var lastRun: @Sendable () -> Date?
        public var setLastRun: @Sendable (Date) -> Void
        public var now: @Sendable () -> Date

        public init(
            environment: @escaping @Sendable () async -> [String: String]?,
            config: @escaping @Sendable ([String: String]) async -> HomebrewConfig?,
            idle: @escaping @Sendable () async -> Bool,
            update: @escaping @Sendable ([String: String]) async throws -> Void,
            lastRun: @escaping @Sendable () -> Date?,
            setLastRun: @escaping @Sendable (Date) -> Void,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.environment = environment
            self.config = config
            self.idle = idle
            self.update = update
            self.lastRun = lastRun
            self.setLastRun = setLastRun
            self.now = now
        }
    }

    private let seams: Seams
    /// The last read of the user's settings, and when it was made.
    private var settings: (environment: [String: String]?, config: HomebrewConfig?, at: Date)?

    public init(_ seams: Seams) {
        self.seams = seams
    }

    /// The period `config` allows between two runs.
    public static func period(_ config: HomebrewConfig) -> TimeInterval {
        config.autoUpdateSeconds.map(TimeInterval.init) ?? defaultPeriod
    }

    /// One tick of the app's schedule. `interval` is the app's check interval;
    /// nil is "Only when I check", and then nothing runs — a tick already under
    /// way when the user chose it must not start a `brew update`.
    public func runIfDue(interval: TimeInterval?) async -> Outcome {
        guard interval != nil else { return .manual }
        let now = seams.now()
        if settings.map({ now.timeIntervalSince($0.at) >= Self.settingsTTL }) ?? true {
            let environment = await seams.environment()
            var config: HomebrewConfig?
            if let environment { config = await seams.config(environment) }
            settings = (environment, config, now)
        }
        guard let environment = settings?.environment, let config = settings?.config else { return .unreadable }
        guard !config.autoUpdateDisabled else { return .disabled }
        if let last = seams.lastRun(), now.timeIntervalSince(last) < Self.period(config) { return .notDue }
        guard await seams.idle() else { return .busy }
        seams.setLastRun(now)
        do {
            try await seams.update(environment)
            return .updated
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
