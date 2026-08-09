import Testing
import Foundation
@testable import DuoUpdaterCore

/// `AppRestarter` drives real processes, so these only cover what's pure: the
/// bundle-path match `runningInstances(of:)` filters on, and the outcomes for
/// inputs that are guaranteed never to find (let alone quit) a live process —
/// no test here ever calls `terminate()` on anything real.
@Suite struct AppRestarterTests {

    private func app(
        bundleID: String? = "com.example.fixture", path: String = "/Applications/Fixture.app"
    ) -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: bundleID, shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// The reason `runningInstances(of:)` matches on path rather than bundle id:
    /// channel siblings like Android Studio Preview and Stable share one bundle
    /// id but live at different paths, and only the exact-path install should be
    /// quit.
    @Test func differentPathsWithTheSameBundleIDDoNotMatch() {
        let target = UpdatePolicy.runtimeBundlePath(
            URL(fileURLWithPath: "/Applications/Android Studio.app"))
        let sibling = URL(fileURLWithPath: "/Applications/Android Studio Preview.app")
        #expect(!AppRestarter.matchesBundlePath(sibling, target: target))
    }

    @Test func theExactBundlePathMatches() {
        let path = URL(fileURLWithPath: "/Applications/Fixture.app")
        let target = UpdatePolicy.runtimeBundlePath(path)
        #expect(AppRestarter.matchesBundlePath(path, target: target))
    }

    /// A running instance with no bundle URL (can happen for odd processes) is
    /// never treated as a match.
    @Test func aNilCandidateURLNeverMatches() {
        #expect(!AppRestarter.matchesBundlePath(nil, target: "/Applications/Fixture.app"))
    }

    /// DuoUpdater's own staging rename must still resolve back to the live
    /// bundle, or a hot-swapped process would look like a different app and
    /// never be found to quit.
    @Test func aStagedRenameStillMatchesTheLiveBundle() {
        let live = URL(fileURLWithPath: "/Applications/Fixture.app")
        let staged = URL(fileURLWithPath: "/Applications/.duoupdater-staged-Fixture.app")
        let target = UpdatePolicy.runtimeBundlePath(live)
        #expect(AppRestarter.matchesBundlePath(staged, target: target))
    }

    /// An app with no `CFBundleIdentifier` is never touched — there's nothing
    /// reliable to match a running instance against.
    @Test func anAppWithNoBundleIDIsSkipped() async {
        let outcome = await AppRestarter.restart(app(bundleID: nil))
        #expect(outcome == .noBundleID)
    }

    /// A fixture bundle id that (in practice) matches no real running process —
    /// this is what keeps the test from ever calling `terminate()` on anything.
    @Test func anAppWithNoRunningInstanceIsANoOp() async {
        let outcome = await AppRestarter.restart(app())
        #expect(outcome == .notRunning)
    }
}
