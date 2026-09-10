import Testing
import Foundation
@testable import DuoUpdaterCore

/// The half of `BuildLineage` that `SuperconductorTests` cannot reach without the
/// network: what the probe does when the second document is missing, stale, or
/// unreadable. Every case but the first must FAIL the probe — a remote that
/// arrives without its lineage would be ordered by `VersionComparator`, which on
/// commit hashes is a coin flip.
///
/// Driven through the real `probeOutcome`, against a local stub, with the
/// registry's own patterns. Each test serves its documents on its own host, so the
/// tests can run in parallel without reading each other's bodies.
struct SuperconductorProbeTests {

    private final class DocumentServer: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var documents: [String: (status: Int, body: String)] = [:]

        static func serve(_ url: URL, status: Int = 200, _ body: String) {
            lock.lock(); defer { lock.unlock() }
            documents[url.absoluteString] = (status, body)
        }

        private static func document(_ url: URL) -> (status: Int, body: String)? {
            lock.lock(); defer { lock.unlock() }
            return documents[url.absoluteString]
        }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DocumentServer.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, let document = Self.document(url) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let response = HTTPURLResponse(
                url: url, statusCode: document.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(document.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// The registered recipe's patterns and install spec, pointed at `host`.
    private static func recipe(host: String) throws -> (VendorProbeRecipe, latest: URL, lineage: URL) {
        let registered = try SuperconductorTests.recipe()
        let spec = try #require(registered.buildLineage)
        let latest = URL(string: "https://\(host)/latest.json")!
        let lineage = URL(string: "https://\(host)/changelog.json")!
        let recipe = VendorProbeRecipe(
            bundleID: registered.bundleID, url: latest, mode: registered.mode,
            versionPattern: registered.versionPattern,
            publishedAtPattern: registered.publishedAtPattern,
            install: registered.install,
            buildLineage: .init(url: lineage, entryPattern: spec.entryPattern))
        return (recipe, latest, lineage)
    }

    private static func probe(_ recipe: VendorProbeRecipe) async -> ProbeOutcome {
        await VendorProbeSource(recipes: [], session: DocumentServer.session())
            .probeOutcome(recipe)
    }

    @Test func whenBothDocumentsAgreeTheRemoteCarriesTheLineage() async throws {
        let (recipe, latest, lineage) = try Self.recipe(host: "agree.example.invalid")
        DocumentServer.serve(latest, SuperconductorTests.latestBody)
        DocumentServer.serve(lineage, SuperconductorTests.changelogBody)

        let outcome = await Self.probe(recipe)
        #expect(outcome.failure == nil)
        let remote = try #require(outcome.remote)
        #expect(remote.displayVersion == SuperconductorTests.installedBuild)
        #expect(remote.buildLineage?.newestFirst == SuperconductorTests.historyHead)
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// The two documents are published separately; a check between them must not
    /// answer with a version it cannot place.
    @Test func aLineageThatDoesNotListTheVersionFailsTheProbe() async throws {
        let (recipe, latest, lineage) = try Self.recipe(host: "stale.example.invalid")
        DocumentServer.serve(latest, SuperconductorTests.latestBody)
        DocumentServer.serve(lineage, #"{"releases": [{"version": "19d32d9a7d16fc3ccaaa7cfe606b45b90a257b13"}]}"#)

        let outcome = await Self.probe(recipe)
        #expect(outcome.remote == nil)
        #expect(outcome.failure == .buildLineageMissesVersion(SuperconductorTests.installedBuild))
        #expect(outcome.failure?.classification == .infra)
    }

    @Test func aLineageWhosePatternMatchesNothingFailsTheProbe() async throws {
        let (recipe, latest, lineage) = try Self.recipe(host: "reshaped.example.invalid")
        DocumentServer.serve(latest, SuperconductorTests.latestBody)
        DocumentServer.serve(lineage, #"{"builds": [{"id": "8545a7d8"}]}"#)

        let outcome = await Self.probe(recipe)
        #expect(outcome.remote == nil)
        guard case .buildLineagePatternNoMatch? = outcome.failure else {
            Issue.record("expected buildLineagePatternNoMatch, got \(String(describing: outcome.failure))")
            return
        }
        #expect(outcome.failure?.classification == .recipe)
        // The sample is the document that stopped matching, not the version body.
        #expect(outcome.bodySample?.contains("builds") == true)
    }

    @Test func anUnreachableLineageFailsTheProbe() async throws {
        let (recipe, latest, lineage) = try Self.recipe(host: "gone.example.invalid")
        DocumentServer.serve(latest, SuperconductorTests.latestBody)
        DocumentServer.serve(lineage, status: 404, "not found")

        let outcome = await Self.probe(recipe)
        #expect(outcome.remote == nil)
        // Named as the release-order document's failure, not the version endpoint's.
        #expect(outcome.failure == .buildLineageUnavailable(.httpStatus(404)))
        #expect(outcome.failure?.classification == .recipe)
    }
}
