import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewFormulaReleaseService` runs `brew info` (a ~0.5s subprocess) on the way to
/// a formula's notes. That work must never occupy the actor: `prewarmFormulaReleases`
/// enqueues one `release(...)` per outdated formula, and the interactive path
/// (`ensureFormulaReleaseLoading`, on user select) shares the same actor. When the
/// subprocess is called synchronously from an actor-isolated method it holds the
/// actor for its whole duration, so the chain serializes and a formula whose notes
/// are ALREADY on disk still spins for N x 0.5s behind it.
@Suite(.serialized)
struct BrewFormulaReleaseActorTests {
    /// Fails instantly, so `fetchRelease` can never reach the real GitHub API — this
    /// test is about the local subprocess, and must not spend rate limit to say so.
    private final class OfflineProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }

    private static func offlineSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A disk-cached formula must stay instantly readable while a prewarm-sized batch
    /// of uncached `release(...)` calls is in flight. Guards the executor hop in
    /// `brewInfoOffActor`: revert it to a synchronous `Self.brewInfo(name:)` and the
    /// `cached(...)` below queues behind every subprocess in the batch instead.
    @Test func cachedStaysResponsiveWhileUncachedFormulaeAreComputing() async throws {
        // `brew info` is what blocks; with no brew there is no subprocess to serialize
        // behind and the test would pass vacuously.
        try #require(HomebrewInstaller.brewPath() != nil, "needs Homebrew installed")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewFormulaReleaseActorTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = BrewFormulaReleaseService(session: Self.offlineSession(), cacheDirectory: dir)

        // Seeded through `persist` rather than a hand-written file: it stamps the
        // running `Changelog.parserGeneration`, so this can't drift from the on-disk
        // format the way a literal fixture does. Same reason
        // `BrewFormulaReleaseServiceTests` uses it — see `persist`'s doc comment.
        let cachedName = "duocachedformula"
        let cachedVersion = "1.0.0"
        let seeded = FormulaRelease(
            changelog: nil, pageURL: URL(string: "https://example.com/notes"))
        await service.persist(seeded, name: cachedName, version: cachedVersion)

        // Guard against a vacuous pass: a `cached` that misses returns nil instantly,
        // and the timing assertion below would then prove nothing.
        #expect(await service.cached(for: cachedName, version: cachedVersion) == seeded,
                "seeded entry must be readable before timing it")

        // A prewarm-sized batch of uncached formulae, each paying a full `brew info`.
        let batch = 4
        let inFlight = (0..<batch).map { i in
            Task {
                _ = await service.release(
                    for: "duo-uncached-formula-\(i)", version: "9.9.9", token: nil)
            }
        }
        defer { for task in inFlight { task.cancel() } }

        // Let the batch enter the actor before timing the interactive read.
        try await Task.sleep(nanoseconds: 100_000_000)

        let start = Date()
        let hit = await service.cached(for: cachedName, version: cachedVersion)
        let elapsed = Date().timeIntervalSince(start)

        #expect(hit == seeded)
        // Each `brew info` costs ~0.5s+, so the serialized form would take multiple
        // seconds to answer here. Generous bound: this is about seconds-vs-instant,
        // not about measuring the disk read.
        #expect(elapsed < 0.5, "cached() waited \(elapsed)s behind the brew info batch")

        for task in inFlight { await task.value }
    }
}
