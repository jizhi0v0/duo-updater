import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewRefreshPolicy`: which triggers re-read brew's package list, and the
/// ten seconds an open or a focus waits after a read. Each case names the
/// mutation it fails under.
struct BrewRefreshPolicyTests {

    func runs(_ trigger: RefreshTrigger, since: Duration?, ours: Bool = false, idle: Bool = true) -> Bool {
        BrewRefreshPolicy.decide(trigger, sinceLastRead: since, ourBrewRunGoing: ours, brewIsIdle: idle).runs
    }

    /// An open or a focus within `spacing` of the last read asks nothing; at
    /// `spacing` it reads again. Before any read, it reads.
    ///
    /// Mutations: drop the `spaced` check from either case; `<=` for `<`.
    @Test(arguments: [RefreshTrigger.popoverOpen, .workbenchOpen, .workbenchFocus])
    func opensAndFocusesAreSpaced(_ trigger: RefreshTrigger) {
        #expect(runs(trigger, since: nil))
        #expect(!runs(trigger, since: .zero))
        #expect(!runs(trigger, since: BrewRefreshPolicy.spacing - .milliseconds(1)))
        #expect(runs(trigger, since: BrewRefreshPolicy.spacing))
    }

    /// A re-read after our own brew run, and the schedule's tick, are not
    /// spaced: either may follow a `brew` run that changed the list.
    ///
    /// Mutation: the `spaced` check moved above the `switch`.
    @Test(arguments: [RefreshTrigger.afterAction("brew upgrade"), .backgroundTick(interval: 300)])
    func ourRunsAndTicksAreNotSpaced(_ trigger: RefreshTrigger) {
        #expect(runs(trigger, since: .zero))
    }

    /// A focus while one of our brew runs is going, or a tick while brew is
    /// busy with ours or a cask install, asks nothing: that run re-reads when
    /// it ends.
    ///
    /// Mutations: drop the `ourBrewRunGoing` guard; drop the `brewIsIdle` guard.
    @Test func ourBrewRunsHoldFocusesAndTicks() {
        #expect(!runs(.workbenchFocus, since: nil, ours: true))
        #expect(runs(.popoverOpen, since: nil, ours: true))
        #expect(!runs(.backgroundTick(interval: 300), since: nil, idle: false))
        #expect(runs(.afterAction("brew update"), since: nil, ours: true, idle: false))
    }
}
