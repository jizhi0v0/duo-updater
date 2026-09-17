import Foundation
import Testing
@testable import DuoUpdaterCore

/// The two relaunch decisions that used to live inside `AppListModel`, where no
/// test could reach them — `App/project.yml` declares six targets and only
/// `DuoUpdaterAppTests` is a test, compiling only the sources it names, and
/// `AppListModel` is not among them. Both were wrong in the same way, and the
/// wrongness was only visible on an app whose marketing version does not move
/// between builds.
///
/// Every fixture here is the Amp shape: `CFBundleShortVersionString` frozen at
/// "1.0" while `CFBundleVersion` climbs. Measured 2026-08-28 — Amp shipped ten
/// builds that day, all called "1.0".
@Suite struct RelaunchProgressTests {

    private func amp(_ build: String?) -> VersionSide {
        VersionSide(marketing: "1.0", build: build)
    }

    // MARK: - hasLanded (the Relaunch spinner's predicate)

    /// The bug the user actually saw: Relaunch spun for its full 900 ticks
    /// (189 s observed) and then logged `applied=false` — for a swap that had
    /// already succeeded and relaunched the app on the new build.
    @Test func aBuildOnlySwapCountsAsLanded() {
        #expect(RelaunchProgress.hasLanded(old: amp("128"), disk: amp("129")),
                "128 → 129 is a landing; only the build moved, which is the whole point")
    }

    /// The other direction, so the fix cannot become "always true": nothing has
    /// happened yet, and reopening here is what makes a ShipIt with the
    /// running-instances check abort with "App Still Running Error".
    @Test func anUnchangedBundleHasNotLanded() {
        #expect(!RelaunchProgress.hasLanded(old: amp("128"), disk: amp("128")))
    }

    /// A bundle mid-swap can be unreadable. That is not evidence of a landing,
    /// and treating it as one would reopen the app on top of its own updater.
    @Test func anUnreadableBundleIsNotALanding() {
        #expect(!RelaunchProgress.hasLanded(old: amp("128"), disk: VersionSide()))
        #expect(!RelaunchProgress.hasLanded(old: VersionSide(), disk: amp("129")))
    }

    /// Marketing still decides when it actually moves — the ordinary case, which
    /// must not regress while fixing the frozen one.
    @Test func aMarketingBumpStillCountsWithNoBuildsAtAll() {
        #expect(RelaunchProgress.hasLanded(
            old: VersionSide(marketing: "1.7.3"), disk: VersionSide(marketing: "1.8.0")))
        #expect(!RelaunchProgress.hasLanded(
            old: VersionSide(marketing: "1.8.0"), disk: VersionSide(marketing: "1.7.3")))
    }

    // MARK: - RelaunchLanding.isSatisfied

    /// `.stagedSwap` used to be `disk == target`, with both sides marketing — so
    /// for Amp it was satisfied *before* the swap, and the relay would reopen the
    /// app while its updater was still working.
    @Test func aStagedSwapIsNotSatisfiedUntilTheBuildArrives() {
        let landing = RelaunchLanding.stagedSwap(to: amp("130"))
        #expect(!landing.isSatisfied(byDisk: amp("129")), "129 is not yet 130")
        #expect(landing.isSatisfied(byDisk: amp("130")), "exactly the staged build")
        #expect(landing.isSatisfied(byDisk: amp("131")),
                "the app may have moved past the build we waited for")
        #expect(!landing.isSatisfied(byDisk: VersionSide()), "unreadable is not landed")
    }

    /// `.appStoreSwap` is strictly-newer on purpose: its payload is the version
    /// installed BEFORE, so equality means the store delivered nothing.
    @Test func anAppStoreSwapNeedsAStrictlyNewerBuild() {
        let landing = RelaunchLanding.appStoreSwap(past: amp("128"))
        #expect(!landing.isSatisfied(byDisk: amp("128")))
        #expect(landing.isSatisfied(byDisk: amp("129")))
    }

    /// `.applied` was already swapped before we asked for the quit, so it needs
    /// nothing off disk — and must not be made to poll for it.
    @Test func appliedNeedsNothingFromDisk() {
        #expect(RelaunchLanding.applied.isSatisfied(byDisk: VersionSide()))
        #expect(!RelaunchLanding.applied.waitsForDisk)
        #expect(RelaunchLanding.stagedSwap(to: amp("130")).waitsForDisk)
    }

    /// Only the App Store case reopens without a landing — we closed the user's
    /// app ourselves there, so it comes back regardless.
    @Test func onlyTheAppStoreLandingReopensWithoutLanding() {
        #expect(RelaunchLanding.appStoreSwap(past: amp("128")).launchesWithoutLanding)
        #expect(!RelaunchLanding.stagedSwap(to: amp("130")).launchesWithoutLanding)
        #expect(!RelaunchLanding.applied.launchesWithoutLanding)
    }

    // MARK: - Swap-on-launch (Spotify)

    /// The 2026-09-14 hang: Spotify only swaps when opened again, so a landing
    /// that polls disk *before* launching waits out its whole budget for nothing.
    /// `.stagedOnLaunch` must launch first and poll after.
    @Test func aSwapOnLaunchLaunchesBeforeWaiting() {
        let landing = RelaunchLanding.stagedOnLaunch(to: amp("130"))
        #expect(!landing.waitsForDisk, "nothing lands until we launch it")
        #expect(landing.landsAfterLaunch)
        #expect(!RelaunchLanding.stagedSwap(to: amp("130")).landsAfterLaunch,
                "ShipIt must still be left alone until disk moves")
        #expect(!RelaunchLanding.applied.landsAfterLaunch)
        #expect(!RelaunchLanding.appStoreSwap(past: amp("128")).landsAfterLaunch)
    }

    /// Once launched it waits for the same thing a staged swap does.
    @Test func aSwapOnLaunchIsSatisfiedLikeAStagedSwap() {
        let landing = RelaunchLanding.stagedOnLaunch(to: amp("130"))
        #expect(!landing.isSatisfied(byDisk: amp("129")))
        #expect(landing.isSatisfied(byDisk: amp("130")))
        #expect(landing.isSatisfied(byDisk: amp("131")))
        #expect(!landing.isSatisfied(byDisk: VersionSide()))
    }

    /// The staged build's trigger picks the order — the only mapping there is.
    @Test func theStagedTriggerPicksTheLanding() {
        let url = URL(fileURLWithPath: "/ZZFixture/Staged.app")
        let onQuit = StagedSelfUpdate(version: "1.0", buildVersion: "130", stagedBundlePath: url)
        let onLaunch = StagedSelfUpdate(
            version: "1.0", buildVersion: "130", stagedBundlePath: url, appliesOn: .launch)
        #expect(RelaunchLanding.staged(onQuit) == .stagedSwap(to: amp("130")))
        #expect(RelaunchLanding.staged(onLaunch) == .stagedOnLaunch(to: amp("130")))
    }
}

/// The continuous-release window: an armed relaunch marker must survive the
/// vendor shipping another build while the user is still answering a save prompt.
@Suite struct ArmedLandingRetargetTests {

    private func amp(_ build: String) -> VersionSide {
        VersionSide(marketing: "1.0", build: build)
    }

    /// The bug. Marker armed for 130, app stages 131 inside the ten-minute
    /// window, marker dropped — and when the user finally quits, an app staged
    /// with `launchAfterInstallation=false` stays closed with nobody to reopen it.
    @Test func aMarkerSurvivesTheVendorShippingAnotherBuild() {
        let armed = RelaunchLanding.stagedSwap(to: amp("130"))
        let after = armed.retargeted(nowStaged: amp("131"))
        #expect(after != nil, "the app still has a pending swap and the user still asked for a relaunch")
        #expect(after == .stagedSwap(to: amp("131")), "and it now waits for the build that will actually land")
    }

    /// Staging genuinely gone: nothing will land, so the marker is dead.
    @Test func aMarkerIsDroppedWhenStagingDisappears() {
        #expect(RelaunchLanding.stagedSwap(to: amp("130")).retargeted(nowStaged: nil) == nil)
        #expect(RelaunchLanding.stagedSwap(to: amp("130"))
            .retargeted(nowStaged: VersionSide()) == nil)
    }

    /// Unchanged staging keeps the same target — the ordinary case.
    @Test func anUnchangedMarkerIsKept() {
        let armed = RelaunchLanding.stagedSwap(to: amp("130"))
        #expect(armed.retargeted(nowStaged: amp("130")) == armed)
    }

    /// A swap-on-launch marker is retargeted the same way but keeps its order —
    /// turning it into `.stagedSwap` would bring back the wait-before-launch hang.
    @Test func aSwapOnLaunchMarkerKeepsItsKind() {
        let armed = RelaunchLanding.stagedOnLaunch(to: amp("130"))
        #expect(armed.retargeted(nowStaged: amp("131")) == .stagedOnLaunch(to: amp("131")))
        #expect(armed.retargeted(nowStaged: nil) == nil)
    }

    /// The other landings are not derived from the staging area at all: their
    /// build is already on disk, or is the App Store's to deliver. The sweep must
    /// not touch them.
    @Test func otherLandingsAreNeverTouchedBythisSweep() {
        #expect(RelaunchLanding.applied.retargeted(nowStaged: nil) == .applied)
        let store = RelaunchLanding.appStoreSwap(past: amp("128"))
        #expect(store.retargeted(nowStaged: nil) == store)
    }
}

/// The namespace trap found in review: `AppScanner` substitutes a derived build
/// for the bundles in `buildVersionIsOverridden`, so an `InstalledApp`'s build is
/// not always the bundle's own `CFBundleVersion`. Comparing that stored value
/// against a raw plist read is two namespaces, not one.
@Suite struct DerivedBuildComparisonTests {

    /// DoubaoIme's real `CFBundleVersion` is a flat "1" on every build; the
    /// scanner stores the vendor's own number instead. Comparing them would say
    /// "not landed" forever — the exact 900-tick spin this module exists to end.
    @Test func aDerivedBuildIsDroppedRatherThanComparedAgainstARawRead() {
        let scanned = VersionSide(marketing: "1.0", build: "6.1.5")   // scanner's
        let raw = VersionSide(marketing: "1.0", build: "1")           // the bundle's

        #expect(!RelaunchProgress.hasLanded(old: scanned, disk: raw),
                "without the flag the derived build loses to the raw one")
        #expect(!RelaunchProgress.hasLanded(old: scanned, disk: raw, buildIsDerived: true),
                "with it, marketing ties and nothing claims a landing — correct, it has not moved")

        // ...and a real marketing move is still seen, which is all these apps have.
        #expect(RelaunchProgress.hasLanded(
            old: scanned, disk: VersionSide(marketing: "1.1", build: "1"),
            buildIsDerived: true))
    }

    /// The ordinary app is untouched: its build is the bundle's own, so it still
    /// decides when the marketing versions tie.
    @Test func anOrdinaryAppStillUsesItsBuild() {
        #expect(RelaunchProgress.hasLanded(
            old: VersionSide(marketing: "1.0", build: "128"),
            disk: VersionSide(marketing: "1.0", build: "129"),
            buildIsDerived: false))
    }
}

/// What a staged Relaunch tells the user when it stops waiting, and when that
/// red line comes back down. `relaunchStagedUpdate` (App) only wires these.
@Suite struct StagedRelaunchOutcomeTests {

    // MARK: - classify

    /// Mutation: ask `everQuit` before `landed` → red. The poll checks disk first
    /// and stops on a landing, so a quit and swap that both fall between two
    /// polls end with no quit observed; that must still read as applied, not as
    /// an app that wouldn't quit.
    @Test func aLandingWithNoObservedQuitIsApplied() {
        #expect(StagedRelaunchOutcome.classify(
            landed: true, everQuit: false, reappearedWithoutLanding: false) == .applied)
        #expect(StagedRelaunchOutcome.classify(
            landed: true, everQuit: true, reappearedWithoutLanding: false) == .applied)
    }

    /// Mutation: return `.swapDidNotLand` for every non-landing → red. A save
    /// prompt holding the quit is not the updater failing; that path arms a
    /// hand-off and must not paint the row red.
    @Test func neverQuittingIsNotAFailure() {
        #expect(StagedRelaunchOutcome.classify(
            landed: false, everQuit: false, reappearedWithoutLanding: false) == .wontQuit)
    }

    /// Mutation: return `.wontQuit` for every non-landing → red. This is the
    /// silent failure being fixed: the app went down and the bundle never moved.
    @Test func quittingWithoutALandingIsTheFailure() {
        #expect(StagedRelaunchOutcome.classify(
            landed: false, everQuit: true, reappearedWithoutLanding: false) == .swapDidNotLand)
    }

    /// Mutation: ignore `reappearedWithoutLanding` → red. An app running again on
    /// the old bundle must not be told its updater "didn't apply the update in
    /// time" — no amount of time was going to help.
    @Test func aReappearanceIsItsOwnEnding() {
        #expect(StagedRelaunchOutcome.classify(
            landed: false, everQuit: true, reappearedWithoutLanding: true) == .restartedWithoutUpdate)
    }

    /// Mutation: ask `reappearedWithoutLanding` before `landed` → red. A landing
    /// is a success whatever else was seen on the way.
    @Test func aLandingBeatsAReappearance() {
        #expect(StagedRelaunchOutcome.classify(
            landed: true, everQuit: true, reappearedWithoutLanding: true) == .applied)
    }

    // MARK: - ReappearanceWatch

    /// Feed `watch` one tick per element of `running` starting at `from`, with
    /// the app having quit before the first of them; returns the tick at which it
    /// gave up, if any.
    private func firstGiveUp(
        _ running: [Bool], from: Int = 10, updater: StagedUpdater? = .shipIt,
        everQuit: Bool = true
    ) -> Int? {
        var watch = ReappearanceWatch(for: staged(by: updater))
        for (offset, isRunning) in running.enumerated() {
            if watch.observe(tick: from + offset, running: isRunning, everQuit: everQuit) {
                return from + offset
            }
        }
        return nil
    }

    /// A staged build shaped the way each detector in `SelfUpdaterStaging` emits
    /// it: Spotify's applies on launch, the other two on quit.
    /// `SelfUpdaterStagingTests` / `SparkleStagingTests` pin that the detectors
    /// really set these.
    private func staged(by updater: StagedUpdater?) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: "1.0", buildVersion: "130",
            stagedBundlePath: URL(fileURLWithPath: "/ZZFixture/Staged.app"),
            appliesOn: updater == .spotify ? .launch : .quit, updater: updater)
    }

    /// A reappearance ends the wait on ShipIt alone. Sparkle waits on the one
    /// instance it registered and swaps anyway when the app is reopened, so
    /// judging it would put up a false "restarted without applying the update"
    /// over a swap that then lands. Mutations: `.sparkle` → true red;
    /// `nil` → true red (an unknown updater must get the full wait); `.shipIt` →
    /// false turns `aReappearanceGivesUpAfterTheGrace` red.
    @Test func onlyShipItIsJudgedByReappearance() {
        let back = [false] + Array(repeating: true, count: 50)
        #expect(firstGiveUp(back, updater: .sparkle) == nil)
        #expect(firstGiveUp(back, updater: nil) == nil)
        #expect(!ReappearanceWatch(for: nil).judgesReappearance,
                "nothing readable staged (an armed Sparkle installer we cannot read) must not fail fast")
    }

    /// The 2026-09-17 case: quit, then back up on the old bundle. Seen at tick 11,
    /// so the verdict comes at tick 16 — five disk reads taken after the sighting,
    /// ~1 s — not at tick 11 and not 180 s later. Literal ticks on purpose, so a
    /// changed grace shows up here. Mutations: give up on the sighting tick (grace
    /// 0) → red; `>` instead of `>=` → red.
    @Test func aReappearanceGivesUpAfterTheGrace() {
        // tick 10: gone; ticks 11…: running again
        #expect(firstGiveUp([false] + Array(repeating: true, count: 20)) == 16)
    }

    /// Mutation: keep `firstSeenTick` when the app is gone again → red. A brief
    /// reappearance that goes away is not a verdict; the clock starts over.
    @Test func goingAwayAgainRestartsTheGrace() {
        // 10 gone, 11–12 up, 13 gone, 14… up → counts from 14
        let ticks = [false, true, true, false] + Array(repeating: true, count: 20)
        #expect(firstGiveUp(ticks) == 19)
    }

    /// Mutation: `.spotify` → true red. For Spotify we launch the old build
    /// ourselves; a new pid there is the next step, not a verdict.
    @Test func aSwapOnLaunchIsNeverJudgedByReappearance() {
        #expect(firstGiveUp([false] + Array(repeating: true, count: 50), updater: .spotify) == nil)
    }

    /// Mutation: drop the `everQuit` guard → red. Still up because it never went
    /// down is the save-prompt path (`wontQuit`), which has its own rule.
    @Test func anAppThatNeverQuitIsNotAReappearance() {
        #expect(firstGiveUp(Array(repeating: true, count: 50), everQuit: false) == nil)
    }

    // MARK: - retractable

    private let id = "/Applications/ZZFixture-Staged.app"
    private let message = "ZZFixture quit, but its own updater didn’t apply the update in time."
    private func amp(_ build: String) -> VersionSide { VersionSide(marketing: "1.0", build: build) }
    private var failure: [String: StagedRelaunchFailure] {
        [id: StagedRelaunchFailure(message: message, old: amp("128"), buildIsDerived: false)]
    }

    /// The update landed after we stopped waiting — a build-only move, the Amp
    /// shape. Mutation: compare `old.marketing` alone → red.
    @Test func aLateLandingRetractsTheLine() {
        #expect(StagedRelaunchFailure.retractable(
            failure, errors: [id: message], installed: [id: amp("129")]) == [id])
    }

    /// An app whose build the scanner overrides is judged the way the wait judged
    /// it: marketing only. Mutation: ignore `failure.buildIsDerived` → red.
    @Test func aDerivedBuildRetractsOnlyOnAMarketingMove() {
        let derived = [id: StagedRelaunchFailure(message: message, old: amp("128"), buildIsDerived: true)]
        #expect(StagedRelaunchFailure.retractable(
            derived, errors: [id: message], installed: [id: amp("129")]).isEmpty)
        #expect(StagedRelaunchFailure.retractable(
            derived, errors: [id: message],
            installed: [id: VersionSide(marketing: "1.1", build: "129")]) == [id])
    }

    /// Mutation: retract whenever the row is present → red. Nothing moved, so
    /// the line is still true.
    @Test func nothingMovedKeepsTheLine() {
        #expect(StagedRelaunchFailure.retractable(
            failure, errors: [id: message], installed: [id: amp("128")]).isEmpty)
    }

    /// Mutation: drop the `errors[id] == message` match → red. An install that
    /// failed since then wrote its own error; a later landing of the staged
    /// build must not erase that one.
    @Test func someoneElsesErrorIsLeftAlone() {
        #expect(StagedRelaunchFailure.retractable(
            failure, errors: [id: "ZZFixture install failed"], installed: [id: amp("129")]).isEmpty)
    }

    /// The app was removed: nothing left for the line to describe. An empty
    /// `installed` is the pre-first-scan state and retracts nothing. Mutation:
    /// drop the `installed.isEmpty` guard → red.
    @Test func aVanishedRowRetractsButNoRowsAtAllDoNot() {
        #expect(StagedRelaunchFailure.retractable(
            failure, errors: [id: message],
            installed: ["/Applications/ZZFixture-Other.app": amp("1")]) == [id])
        #expect(StagedRelaunchFailure.retractable(
            failure, errors: [id: message], installed: [:]).isEmpty)
    }
}
