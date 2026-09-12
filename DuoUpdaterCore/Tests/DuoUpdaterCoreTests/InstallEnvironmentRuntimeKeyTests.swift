import Testing
import Foundation
@testable import DuoUpdaterCore

/// `InstallEnvironment.runtimeKeys` — the precomputed answer the row-level
/// questions use instead of resolving a path per row per redraw.
///
/// **How the seam works.** `UpdatePolicy.runtimeBundlePath` opens with
/// `resolvingSymlinksInPath()`, a filesystem call, and nothing in these tests can
/// count a `realpath`. So the map is used the way `RunningBundlePathCache`'s
/// injectable `resolver` is: it is given an answer the resolver provably would
/// never produce for that path, and the question is which of the two came out.
/// A map entry that lies is not a state production can reach — the host builds
/// the map by calling that very function — it is how the call is observed.
///
/// Every path here is invented and asserted absent: `resolvingSymlinksInPath` is
/// existence-sensitive, so a fixture that happened to exist on the host would put
/// the filesystem into the answer (CLAUDE.md, "测试不能问宿主「你装了什么」").
struct InstallEnvironmentRuntimeKeyTests {

    /// A path no machine has, and the sentinel a resolver could not invent for it.
    private static let rawPath = "/ZZFixture-RuntimeKey/Raw.app"
    private static let precomputed = "/ZZFixture-RuntimeKey/Precomputed.app"

    private func app(path: String) -> InstalledApp {
        #expect(!FileManager.default.fileExists(atPath: path),
                "fixture paths must not exist, or the resolver's answer becomes a fact about this Mac")
        return InstalledApp(
            name: "Fixture", bundleID: "com.example.zzfixture",
            shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: path),
            isMASApp: false, sparkleFeedURL: nil)
    }

    private func result(path: String) -> UpdateResult {
        UpdateResult(app: app(path: path), remote: nil, status: .upToDate)
    }

    /// The point of the whole change: `isRunning` answers from the map, so a
    /// redraw costs a dictionary lookup rather than a `realpath`.
    ///
    /// Mutation: put `runtimeBundlePath(result.app.path)` back into `isRunning`
    /// and this fails — the raw path is what gets compared, and it is not in
    /// `runningAppPaths`.
    @Test func isRunningAnswersFromThePrecomputedKey() {
        let row = result(path: Self.rawPath)
        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: [Self.precomputed],
            stagedSelfUpdates: [:],
            runtimeKeys: [URL(fileURLWithPath: Self.rawPath): Self.precomputed])

        #expect(UpdatePolicy.isRunning(row, environment: environment))
        #expect(UpdatePolicy.runtimeBundlePath(row.app.path) != Self.precomputed,
                "the seam only proves anything while the resolver disagrees with the map")
    }

    /// The same for the elevation question, which shares the call.
    @Test func requiresElevatedInstallAnswersFromThePrecomputedKey() {
        let row = result(path: Self.rawPath)
        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: [],
            stagedSelfUpdates: [:],
            elevationRequiredPaths: [Self.precomputed],
            runtimeKeys: [URL(fileURLWithPath: Self.rawPath): Self.precomputed])

        #expect(UpdatePolicy.requiresElevatedInstall(row, environment: environment))
    }

    /// A host that precomputes nothing — every CLI call site — must be unchanged:
    /// the resolver still runs, including its staging-name rewrite, which is the
    /// half of `runtimeBundlePath` that is not optional.
    ///
    /// Mutation: drop the `?? UpdatePolicy.runtimeBundlePath(url)` fallback and
    /// this fails; the staged path would never match the live one.
    @Test func anEmptyMapStillResolves() {
        let staged = "/ZZFixture-RuntimeKey/.duoupdater-staged-Live.app"
        let live = "/ZZFixture-RuntimeKey/Live.app"
        let row = result(path: staged)
        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: [live],
            stagedSelfUpdates: [:])

        #expect(UpdatePolicy.isRunning(row, environment: environment))
    }

    /// And a map that covers OTHER rows must not answer for this one.
    @Test func aMissEntryFallsBackRatherThanReadingAnotherRowsKey() {
        let row = result(path: Self.rawPath)
        let environment = InstallEnvironment(
            isHelperEnabled: false,
            runningAppPaths: [Self.precomputed],
            stagedSelfUpdates: [:],
            runtimeKeys: [URL(fileURLWithPath: "/ZZFixture-RuntimeKey/Other.app"): Self.precomputed])

        #expect(!UpdatePolicy.isRunning(row, environment: environment))
    }
}
