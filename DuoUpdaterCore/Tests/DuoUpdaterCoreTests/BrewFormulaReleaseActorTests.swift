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
/// Gated, not `#require`d: a `#require` failure is a test FAILURE, and this is the
/// only test in the repo that needs Homebrew installed — the sibling
/// `BrewFormulaReleaseServiceTests` goes out of its way to avoid that. On a
/// brew-less runner there is no subprocess to serialize behind, so the right
/// outcome is "not applicable", not "broken".
@Suite(.serialized, .enabled(if: HomebrewInstaller.brewPath() != nil,
                             "needs Homebrew: the premise is that `brew info` is slow"))
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
        let batchStart = Date()
        let inFlight = (0..<batch).map { i in
            Task {
                _ = await service.release(
                    for: "duo-uncached-formula-\(i)", version: "9.9.9", token: nil)
            }
        }
        defer { for task in inFlight { task.cancel() } }

        // Let the batch enter the actor before timing the interactive read.
        try await Task.sleep(nanoseconds: 100_000_000)

        let bound = 0.2
        let start = Date()
        let hit = await service.cached(for: cachedName, version: cachedVersion)
        let elapsed = Date().timeIntervalSince(start)

        #expect(hit == seeded)
        // Under ONE subprocess (~0.55s), not under the whole batch. Actors make no FIFO
        // admission promise, so a bound of 4x-a-subprocess would still pass if `cached`
        // happened to be admitted after only one `brewInfo` — which is the bug.
        #expect(elapsed < bound, "cached() waited \(elapsed)s behind the brew info batch")

        for task in inFlight { await task.value }
        let batchElapsed = Date().timeIntervalSince(batchStart)

        // Vacuity guard on this test's own premise. It can only tell "actor held" from
        // "actor free" while `brew info` is genuinely slow; if it ever gets fast, the
        // serialized form drops under `bound` and this test passes while proving
        // nothing. The batch runs concurrently, so its wall clock ~= one subprocess and
        // the serialized cost ~= batch x that. Fail loudly the day that stops being
        // true, rather than going quietly green.
        let serializedEstimate = Double(batch) * batchElapsed
        #expect(serializedEstimate > 3 * bound, """
            premise gone: `brew info` is now fast enough that the serialized form \
            (~\(serializedEstimate)s) no longer clears the \(bound)s bound, so a pass \
            here proves nothing. Re-tune or delete this test.
            """)
    }
}
