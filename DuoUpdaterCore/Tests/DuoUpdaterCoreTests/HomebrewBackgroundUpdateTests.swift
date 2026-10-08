import Foundation
import Testing
@testable import DuoUpdaterCore

/// `HomebrewBackgroundUpdate`'s decisions, with every seam scripted: no login
/// shell, no `brew`, no UserDefaults. The user's Homebrew must not be updated
/// because a test ran.
struct HomebrewBackgroundUpdateTests {

    /// Everything the seams read and every call they saw.
    final class Fake: @unchecked Sendable {
        var environment: [String: String]? = ["HOMEBREW_DEVELOPER": "1"]
        var config: HomebrewConfig? = HomebrewConfig(version: "7.0.8", autoUpdateDisabled: false)
        var idle = true
        var failure: String?
        /// The persisted last run, shared by every instance made from this fake —
        /// what survives a relaunch.
        var lastRun: Date?
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        private(set) var environmentReads = 0
        private(set) var updates: [[String: String]] = []

        struct Failed: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        func make() -> HomebrewBackgroundUpdate {
            HomebrewBackgroundUpdate(.init(
                environment: { self.environmentReads += 1; return self.environment },
                config: { _ in self.config },
                idle: { self.idle },
                update: { environment in
                    self.updates.append(environment)
                    if let failure = self.failure { throw Failed(message: failure) }
                },
                lastRun: { self.lastRun },
                setLastRun: { self.lastRun = $0 },
                now: { self.now }))
        }
    }

    static let schedule: TimeInterval = 5 * 60
    static let hour: TimeInterval = 60 * 60

    // MARK: brew config

    /// `brew config` lists `HOMEBREW_AUTO_UPDATE_SECS` only when the user set it
    /// to something other than the default; a value that is not a whole number
    /// is read as unset.
    ///
    /// Mutation: drop the `HOMEBREW_AUTO_UPDATE_SECS` branch from `parse`.
    @Test func theAutoUpdatePeriodIsReadFromBrewConfig() {
        let head = "HOMEBREW_VERSION: 7.0.8\nORIGIN: https://github.com/Homebrew/brew"
        #expect(HomebrewConfig.parse(head + "\nHOMEBREW_AUTO_UPDATE_SECS: 3600")?.autoUpdateSeconds == 3600)
        #expect(HomebrewConfig.parse(head)?.autoUpdateSeconds == nil)
        #expect(HomebrewConfig.parse(head + "\nHOMEBREW_AUTO_UPDATE_SECS: soon")?.autoUpdateSeconds == nil)
    }

    // MARK: when it runs

    /// Once a day without `HOMEBREW_AUTO_UPDATE_SECS`: not 23 hours after the last
    /// run, and at 24 — recorded when it starts.
    ///
    /// Mutations: drop the `notDue` line from `runIfDue`; `period` ignoring
    /// `defaultPeriod` (returning 0).
    @Test func onceADayByDefault() async {
        let fake = Fake()
        let start = fake.now
        fake.lastRun = start.addingTimeInterval(-23 * Self.hour)

        #expect(await fake.make().runIfDue(interval: Self.schedule) == .notDue)
        #expect(fake.updates.isEmpty)

        fake.now = start.addingTimeInterval(Self.hour)
        #expect(await fake.make().runIfDue(interval: Self.schedule) == .updated)
        #expect(fake.updates == [["HOMEBREW_DEVELOPER": "1"]])
        #expect(fake.lastRun == fake.now)
    }

    /// The user's `HOMEBREW_AUTO_UPDATE_SECS` is the period instead.
    ///
    /// Mutation: `period` returning `defaultPeriod` whatever the config says.
    @Test func theUsersAutoUpdatePeriodIsHonoured() async {
        let fake = Fake()
        fake.config = HomebrewConfig(version: "7.0.8", autoUpdateDisabled: false, autoUpdateSeconds: 3600)
        let start = fake.now
        fake.lastRun = start.addingTimeInterval(-59 * 60)
        #expect(await fake.make().runIfDue(interval: Self.schedule) == .notDue)

        fake.now = start.addingTimeInterval(60)
        #expect(await fake.make().runIfDue(interval: Self.schedule) == .updated)
    }

    /// `HOMEBREW_NO_AUTO_UPDATE` set: never, and nothing recorded.
    ///
    /// Mutation: drop `guard !config.autoUpdateDisabled`.
    @Test func neverWhenTheUserTurnedAutoUpdateOff() async {
        let fake = Fake()
        fake.config = HomebrewConfig(version: "7.0.8", autoUpdateDisabled: true)

        #expect(await fake.make().runIfDue(interval: Self.schedule) == .disabled)
        #expect(fake.updates.isEmpty)
        #expect(fake.lastRun == nil)
    }

    /// "Only when I check": nothing runs, and not even the shell is read.
    ///
    /// Mutation: drop `guard interval != nil`.
    @Test func neverUnderManual() async {
        let fake = Fake()

        #expect(await fake.make().runIfDue(interval: nil) == .manual)
        #expect(fake.updates.isEmpty)
        #expect(fake.environmentReads == 0)
    }

    /// Settings that cannot be read are not taken as "nothing set".
    ///
    /// Mutation: run with `[:]` when the environment is nil.
    @Test func unreadableSettingsDoNotRun() async {
        let noShell = Fake()
        noShell.environment = nil
        #expect(await noShell.make().runIfDue(interval: Self.schedule) == .unreadable)
        #expect(noShell.updates.isEmpty)

        let noConfig = Fake()
        noConfig.config = nil
        #expect(await noConfig.make().runIfDue(interval: Self.schedule) == .unreadable)
        #expect(noConfig.updates.isEmpty)
    }

    /// One of DuoUpdater's own brew runs under way: not run, and not recorded, so
    /// the next tick asks again.
    ///
    /// Mutation: drop `guard await seams.idle()`; record the run before asking.
    @Test func notWhileDuoUpdatersOwnBrewRuns() async {
        let fake = Fake()
        fake.idle = false
        let update = fake.make()

        #expect(await update.runIfDue(interval: Self.schedule) == .busy)
        #expect(fake.updates.isEmpty)
        #expect(fake.lastRun == nil)

        fake.idle = true
        #expect(await update.runIfDue(interval: Self.schedule) == .updated)
    }

    /// A failed run counts as a run: the next tick does not retry it.
    @Test func aFailedRunIsNotRetriedOnTheNextTick() async {
        let fake = Fake()
        fake.failure = "fatal: unable to access"
        let update = fake.make()

        #expect(await update.runIfDue(interval: Self.schedule) == .failed("fatal: unable to access"))
        fake.now = fake.now.addingTimeInterval(Self.schedule)
        #expect(await update.runIfDue(interval: Self.schedule) == .notDue)
        #expect(fake.updates.count == 1)
    }

    /// The user's settings are read once an hour, not on every tick — and a
    /// `HOMEBREW_NO_AUTO_UPDATE` set since is seen at the next read.
    ///
    /// Mutation: re-read the settings on every call.
    @Test func theSettingsAreReadOnceAnHour() async {
        let fake = Fake()
        fake.lastRun = fake.now
        let update = fake.make()

        #expect(await update.runIfDue(interval: Self.schedule) == .notDue)
        fake.now = fake.now.addingTimeInterval(Self.schedule)
        #expect(await update.runIfDue(interval: Self.schedule) == .notDue)
        #expect(fake.environmentReads == 1)

        fake.config = HomebrewConfig(version: "7.0.8", autoUpdateDisabled: true)
        fake.now = fake.now.addingTimeInterval(Self.hour)
        #expect(await update.runIfDue(interval: Self.schedule) == .disabled)
        #expect(fake.environmentReads == 2)
    }
}
