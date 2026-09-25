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

    /// `inputMethods` is the same seam for `UpdatePolicy.isInputMethod`: a map
    /// entry that says "input method" for a path the function would clear. A
    /// vendor `.pkg` is handed to the system installer anywhere except an input
    /// method, so which of the two answered is visible in `requiresInstaller`.
    ///
    /// Mutation: put `isInputMethod(result.app.path)` back into
    /// `requiresInstaller` and the first expectation fails.
    @Test func requiresInstallerAnswersFromThePrecomputedInputMethodFlag() {
        let row = UpdateResult(
            app: app(path: Self.rawPath),
            remote: RemoteVersion(
                shortVersion: "2.0", version: nil,
                downloadURL: URL(string: "https://example.com/fixture.pkg"),
                sourceName: "Vendor", vendorInstallerKind: .pkg),
            status: .updateAvailable(latest: "2.0"))
        #expect(!UpdatePolicy.isInputMethod(row.app.path),
                "the seam only proves anything while the function disagrees with the map")

        let flagged = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:],
            inputMethods: [URL(fileURLWithPath: Self.rawPath): true])
        #expect(!UpdatePolicy.requiresInstaller(row, environment: flagged))
        #expect(!UpdatePolicy.canAutoInstall(
            row, settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: flagged))

        // With no entry the function answers, as it always did.
        let unflagged = InstallEnvironment(
            isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        #expect(UpdatePolicy.requiresInstaller(row, environment: unflagged))
        #expect(UpdatePolicy.canAutoInstall(
            row, settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: unflagged))
    }

    /// `InstallPathFacts` is what the host fills those maps from, and its whole
    /// contract is "exactly what the functions answer" — so it is checked against
    /// them, over the shapes each function treats specially: a staged name
    /// (`runtimeBundlePath` rewrites it), an input-method directory
    /// (`isInputMethod` and the elevation exception), and a plain app.
    @Test func pathFactsAreExactlyWhatTheFunctionsAnswer() {
        let bundles = [
            "/ZZFixture-RuntimeKey/.duoupdater-staged-Live.app",
            "/ZZFixture-RuntimeKey/Library/Input Methods/Fixture.app",
            Self.rawPath,
        ].map { path -> URL in
            #expect(!FileManager.default.fileExists(atPath: path))
            return URL(fileURLWithPath: path)
        }
        let facts = InstallPathFacts.observing(bundles)

        #expect(facts.elevationRequiredPaths == InPlaceSwap.elevationRequiredPaths(for: bundles))
        for bundle in bundles {
            #expect(facts.runtimeKeys[bundle] == UpdatePolicy.runtimeBundlePath(bundle))
            #expect(facts.inputMethods[bundle] == UpdatePolicy.isInputMethod(bundle))
        }
        #expect(facts.inputMethods[bundles[1]] == true, "the fixture must exercise the input-method branch")
    }

    /// The host observes a new install on its own and leaves the rest of the list
    /// to the off-main pass, so `observe` must add without disturbing what is
    /// there, and `unobserved` must name exactly the installs it has not seen.
    @Test func observingMoreKeepsWhatWasObserved() {
        let first = URL(fileURLWithPath: Self.rawPath)
        let second = URL(fileURLWithPath: "/ZZFixture-RuntimeKey/Second.app")
        var facts = InstallPathFacts.observing([first])
        #expect(facts.unobserved(in: [first, second]) == [second])

        facts.observe([second])
        #expect(facts.unobserved(in: [first, second]).isEmpty)
        #expect(facts == InstallPathFacts.observing([first, second]))
    }
}
