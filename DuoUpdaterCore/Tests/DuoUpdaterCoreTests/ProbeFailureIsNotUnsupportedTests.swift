import Testing
import Foundation
@testable import DuoUpdaterCore

/// A failed check is not an unsupported app.
///
/// `VendorProbeSource` used to return nil for both, and `UpdateChecker` renders
/// nil-from-everything as `.unknown` — the row's dead "—". So WeChat, whose
/// recipe reads `dldir1.qq.com` and whose only problem was that this Mac's proxy
/// bypass list sent that host down a dead direct path, sat next to a hand-built
/// app that genuinely has no source at all and looked identical: no reason, no
/// retry, nothing to act on. (Found 2026-08-29; the endpoint was serving 200s to
/// anything that went through the proxy the whole time.)
///
/// The split these pin: a recipe that APPLIED and could not answer throws, and
/// only "nothing here covers this app" stays nil.
@Suite struct ProbeFailureIsNotUnsupportedTests {

    private static func app(
        bundleID: String, channel: ReleaseChannel = .stable, isMASApp: Bool = false
    ) -> InstalledApp {
        InstalledApp(
            name: bundleID, bundleID: bundleID,
            shortVersion: "1.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: isMASApp, sparkleFeedURL: nil, releaseChannel: channel)
    }

    private static func recipe(
        bundleID: String = "com.example.subject",
        url: URL,
        pattern: String = #"<version>([0-9.]+)</version>"#,
        identities: [ProbeIdentity] = []
    ) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: bundleID, url: url, mode: .responseBody,
            versionPattern: pattern, identities: identities)
    }

    /// Nothing is listening, so the fetch fails at the transport — the shape of
    /// the WeChat case, and of every "the network went away" round.
    private static let unreachable = URL(string: "http://127.0.0.1:1/feed")!

    // MARK: - a recipe that applied and could not answer

    @Test func anUnreachableEndpointThrowsInsteadOfReadingAsUnsupported() async {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        await #expect(throws: VendorProbeSource.ProbeFailed.self) {
            try await source.latestVersion(for: Self.app(bundleID: "com.example.subject"))
        }
    }

    /// The thrown message must be the CAUSE, with no app identity in it:
    /// `AppListModel.failedCheckSummary` groups failed rows by identical text to
    /// name one reason for the whole cluster, and a per-app string never groups.
    @Test func theThrownMessageNamesTheCauseAndNotTheApp() async throws {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        do {
            _ = try await source.latestVersion(for: Self.app(bundleID: "com.example.subject"))
            Issue.record("expected the probe to throw")
        } catch let failure as VendorProbeSource.ProbeFailed {
            let message = try #require(failure.errorDescription)
            #expect(!message.isEmpty)
            #expect(!message.contains("com.example.subject"))
            // The bare `URLError` message — what the other sources throw, so rows
            // behind one outage carry identical text and group. Specifically NOT
            // the diagnostic `detail`, which prefixes the numeric code and would
            // split one outage into a cluster per code.
            guard case .transport(let code, let carried)? = failure.failure else {
                Issue.record("expected a transport failure, got \(String(describing: failure.failure))")
                return
            }
            #expect(message == carried)
            #expect(failure.failure?.detail == "URLError \(code): \(message)")
        }
    }

    /// The other half of "the recipe applied": the endpoint answered fine and the
    /// pattern matched nothing — a vendor rewriting their page. Also a failed
    /// check, also not an unsupported app.
    @Test func aPatternThatStoppedMatchingThrows() async throws {
        let server = try RecipeVerificationTests.StubServer(
            body: #"{"latest":"2026.2.0.1"}"#)
        defer { server.stop() }
        let source = VendorProbeSource(recipes: [Self.recipe(url: server.url)])

        do {
            _ = try await source.latestVersion(for: Self.app(bundleID: "com.example.subject"))
            Issue.record("expected the probe to throw")
        } catch let failure as VendorProbeSource.ProbeFailed {
            #expect(failure.failure?.kind == "versionPatternNoMatch")
        }
    }

    @Test func aBadStatusThrows() async throws {
        let server = try RecipeVerificationTests.StubServer(status: 404, body: "not found")
        defer { server.stop() }
        let source = VendorProbeSource(recipes: [Self.recipe(url: server.url)])

        do {
            _ = try await source.latestVersion(for: Self.app(bundleID: "com.example.subject"))
            Issue.record("expected the probe to throw")
        } catch let failure as VendorProbeSource.ProbeFailed {
            #expect(failure.failure?.kind == "httpStatus404")
        }
    }

    // MARK: - the cases that still mean "unsupported", and must stay nil

    @Test func noRecipeForTheBundleIDStaysNil() async throws {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        #expect(try await source.latestVersion(for: Self.app(bundleID: "com.example.other")) == nil)
    }

    @Test func aChannelWithNoRecipeStaysNil() async throws {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        let canary = Self.app(bundleID: "com.example.subject", channel: .canary)
        #expect(try await source.latestVersion(for: canary) == nil)
    }

    @Test func anAppStoreCopyStaysNil() async throws {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        let storeCopy = Self.app(bundleID: "com.example.subject", isMASApp: true)
        #expect(try await source.latestVersion(for: storeCopy) == nil)
    }

    /// The subtle one, and the reason this isn't simply "any nil outcome throws":
    /// a recipe keyed to a per-machine identity answers `.notApplicable` when
    /// this Mac has no such file. That IS "this source doesn't cover you" — there
    /// is no endpoint to retry — so it must keep the dash, not become a Failed
    /// badge that re-runs the same missing file forever.
    @Test func anIdentityThisMacDoesNotHaveStaysNil() async throws {
        let identity = ProbeIdentity(
            location: .home(".duo-updater-absent-by-design/identity.json"),
            encoding: .plain,
            validationPattern: #"[a-z0-9-]{1,64}"#,
            placeholder: "__IDENTITY__",
            fallback: nil)  // no fallback: unresolvable, so the recipe cannot apply
        let source = VendorProbeSource(recipes: [
            Self.recipe(
                url: URL(string: "http://127.0.0.1:1/feed?id=__IDENTITY__")!,
                identities: [identity])
        ])

        let outcome = await source.probeDiagnostic(for: Self.app(bundleID: "com.example.subject"))
        // The recipe was selected (an outcome exists) but declined itself.
        #expect(outcome?.failure?.classification == .notApplicable)
        #expect(try await source.latestVersion(for: Self.app(bundleID: "com.example.subject")) == nil)
    }

    // MARK: - what the engine makes of each

    /// End to end: the two halves must reach the UI as DIFFERENT statuses, or
    /// none of the above bought anything.
    @Test func theEngineSeparatesAFailedCheckFromAnUnsupportedApp() async {
        let source = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        let checker = UpdateChecker(sources: [source])

        let failed = await checker.check(Self.app(bundleID: "com.example.subject"))
        guard case .error(let message) = failed.status else {
            Issue.record("a reachable recipe that failed must be .error, got \(failed.status)")
            return
        }
        #expect(!message.isEmpty)

        let uncovered = await checker.check(Self.app(bundleID: "com.example.uncovered"))
        #expect(uncovered.status == .unknown)
    }

    /// Throwing must not change WHICH source answers. The checker continues past
    /// a throw exactly as it does past a nil, so a working source ahead of (or
    /// behind) a failing probe still wins, and no error is reported.
    @Test func aFailingProbeDoesNotSuppressASourceThatAnswers() async throws {
        let server = try RecipeVerificationTests.StubServer(body: "<version>9.9.9</version>")
        defer { server.stop() }
        let failing = VendorProbeSource(recipes: [Self.recipe(url: Self.unreachable)])
        let working = VendorProbeSource(recipes: [Self.recipe(url: server.url)])

        let result = await UpdateChecker(sources: [failing, working])
            .check(Self.app(bundleID: "com.example.subject"))

        #expect(result.status == .updateAvailable(latest: "9.9.9"))
    }
}
