import Foundation
import Testing
@testable import DuoUpdaterCore

/// The two relaunch decisions that used to live inside `AppListModel`, where no
/// test could reach them — `App/project.yml` declares four targets and none of
/// them are tests. Both were wrong in the same way, and the wrongness was only
/// visible on an app whose marketing version does not move between builds.
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
    /// happened yet, and reopening here is what makes ShipIt abort with "App
    /// Still Running Error".
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
