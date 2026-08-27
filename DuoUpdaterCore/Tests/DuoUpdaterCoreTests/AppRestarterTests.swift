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

    // MARK: - The launch timeout

    /// The ordinary case: the work finishes well inside the budget, so its own
    /// answer stands and the timeout never enters into it.
    @Test func anOperationThatFinishesInTimeKeepsItsAnswer() async {
        let value = await AppRestarter.firstToFinish(timeout: .seconds(10), fallback: false) {
            true
        }
        #expect(value)
    }

    /// Past the budget the caller gets `fallback` instead of waiting forever.
    @Test func anOperationPastTheBudgetAnswersWithTheFallback() async {
        let value = await AppRestarter.firstToFinish(timeout: .milliseconds(50), fallback: false) {
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        #expect(!value)
    }

    /// The property the whole thing exists for, and the one a `withTaskGroup`
    /// would quietly fail: giving up must not mean *waiting* for the abandoned
    /// operation. If this regressed, the call would take the operation's 30s
    /// rather than the timeout's 50ms — which is exactly the wedged-launch
    /// behaviour the timeout was added to prevent.
    @Test func givingUpDoesNotWaitForTheAbandonedOperation() async {
        let started = ContinuousClock.now
        _ = await AppRestarter.firstToFinish(timeout: .milliseconds(50), fallback: false) {
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    /// `onTimeout` is the log line, so it must fire only when the budget really
    /// ran out — an operation that answered in time must not be reported as a
    /// timed-out launch.
    @Test func onTimeoutFiresOnlyWhenTheBudgetActuallyRanOut() async {
        let timedOut = Once()
        _ = await AppRestarter.firstToFinish(
            timeout: .seconds(10), fallback: false, onTimeout: { _ = timedOut.claim() }
        ) {
            true
        }
        // Still unclaimed, so `onTimeout` never ran.
        #expect(timedOut.claim())
    }

    /// An app nested inside the target's bundle is an instance of it for quit and
    /// relaunch purposes, and neither existing filter can see one: it carries its
    /// own bundle id, so it never enters the parent's candidate set, and its path
    /// is a child of the target rather than equal to it.
    @Test func anAppNestedInTheBundleCountsAsInside() {
        let target = "/Applications/Surge.app"
        let dashboard = URL(fileURLWithPath:
            "/Applications/Surge.app/Contents/Applications/Surge Dashboard.app")
        #expect(AppRestarter.isNestedInside(dashboard, target: target))
        // …including one already stranded on the moved-aside bundle, which is the
        // state the swap leaves it in and the state we have to recognise to fix it.
        #expect(AppRestarter.isNestedInside(
            URL(fileURLWithPath:
                "/Applications/.duoupdater-staged-Surge.app/Contents/Applications/Surge Dashboard.app"),
            target: target))
    }

    /// The bundle itself is not nested in itself — `runningInstances(of:)` already
    /// owns that one, and counting it twice would terminate it twice and make the
    /// relaunch loop reopen the parent as if it were a helper.
    @Test func theBundleItselfIsNotNestedInItself() {
        let target = "/Applications/Surge.app"
        #expect(!AppRestarter.isNestedInside(URL(fileURLWithPath: target), target: target))
    }

    /// The separator is load-bearing: a prefix test without it reads a sibling
    /// whose name merely starts with the target's as living inside it, and a
    /// Surge update would quit Surge Beta.
    @Test func aSiblingSharingAPrefixIsNotNested() {
        let target = "/Applications/Surge.app"
        #expect(!AppRestarter.isNestedInside(
            URL(fileURLWithPath: "/Applications/Surge Beta.app"), target: target))
        #expect(!AppRestarter.isNestedInside(
            URL(fileURLWithPath: "/Applications/Surge.app.backup/Contents/MacOS/x.app"),
            target: target))
    }

    @Test func nothingIsNestedInsideNoBundleURL() {
        #expect(!AppRestarter.isNestedInside(nil, target: "/Applications/Surge.app"))
    }

    /// Being nested is not enough to be an instance worth quitting.
    ///
    /// The path test alone also matches every Chromium renderer, XPC service and
    /// `.appex` living inside an app bundle. Measured on the development machine:
    /// of 13 nested running processes, only Surge's Dashboard was `.regular` —
    /// `Claude Helper.app`, `Google Chrome Helper.app`,
    /// `WeChatAppEx Helper (Renderer).app`, `cef_server.app`, `DockHelper.xpc` and
    /// `WeatherWidget.appex` were all `.accessory` or `.prohibited`. Terminating
    /// those achieves nothing and relaunching one on its own is incoherent.
    ///
    /// Pinned as paths and policies rather than by driving `NSWorkspace`, which no
    /// test can arrange.
    @Test func onlyAStandaloneNestedAppCountsAsAnInstance() {
        let target = "/Applications/Surge.app"
        // Everything here IS nested — that is the point; the policy is what separates them.
        let nested = [
            "/Applications/Surge.app/Contents/Applications/Surge Dashboard.app",
            "/Applications/Surge.app/Contents/Frameworks/Surge Helper.app",
            "/Applications/Surge.app/Contents/XPCServices/Thing.xpc",
            "/Applications/Surge.app/Contents/PlugIns/Ext.appex",
        ]
        for path in nested {
            #expect(AppRestarter.isNestedInside(URL(fileURLWithPath: path), target: target),
                    "\(path) should read as nested")
        }
        // …and only the `.app` bundles can even reach the policy test.
        #expect(URL(fileURLWithPath: nested[2]).pathExtension != "app")
        #expect(URL(fileURLWithPath: nested[3]).pathExtension != "app")
    }

    // MARK: - Nested-only outcome (#72)

    /// `allNestedBack` is the pure half of the `main.isEmpty` branch: `restart(_:)`
    /// itself can't be driven here (it talks to `NSWorkspace` directly), but the
    /// decision it folds into `.nestedOnly(relaunched:)` — "did every nested app we
    /// tried to bring back actually come back" — is pure and is exactly the piece
    /// issue #72 was about: it must never quietly become `true` when something
    /// didn't come back, or `false` when everything did.
    @Test func allNestedBackIsTrueOnlyWhenEveryOneCameBack() {
        #expect(AppRestarter.allNestedBack([true]))
        #expect(AppRestarter.allNestedBack([true, true]))
        #expect(!AppRestarter.allNestedBack([false]))
        #expect(!AppRestarter.allNestedBack([true, false]))
    }

    /// The `main.isEmpty` branch is only ever reached with at least one nested
    /// app to report on (`running = main + nested` was non-empty and `main` was
    /// empty), but the helper itself must not assume that — an empty result set
    /// answers vacuously true rather than crashing or reading as a failure.
    @Test func allNestedBackOnNoResultsIsVacuouslyTrue() {
        #expect(AppRestarter.allNestedBack([]))
    }
}
