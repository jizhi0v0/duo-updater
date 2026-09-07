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
        let inFlight = (0..<batch).map { i in
            Task {
                _ = await service.release(
                    for: "duo-uncached-formula-\(i)", version: "9.9.9", token: nil)
            }
        }
        defer { for task in inFlight { task.cancel() } }

        // Let the batch enter the actor before timing the interactive read.
        let settle = 0.1
        try await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))

        let start = Date()
        let hit = await service.cached(for: cachedName, version: cachedVersion)
        let elapsed = Date().timeIntervalSince(start)
        #expect(hit == seeded)

        for task in inFlight { await task.value }

        // What one `brew info` costs on THIS host, measured with nothing else on the
        // actor — which is the whole point of taking it here rather than reusing the
        // batch's wall clock. A bound derived from the batch would inflate ~4x in
        // exactly the case this test exists to catch (the batch is serialized when the
        // bug is present), so `batchElapsed / 2` would be ~2 subprocesses of room — and a
        // `cached()` admitted after only one `brewInfo` is the bug, per the reasoning
        // below. Measured 2026-09-07 by reverting the hop: `solo` moved 0.563s -> 0.571s
        // while `batchElapsed` went to 2.459s. The batch is over when this runs, so
        // nothing contends and the number does not inflate with the bug.
        let soloStart = Date()
        _ = await service.release(for: "duo-uncached-formula-solo", version: "9.9.9", token: nil)
        let solo = Date().timeIntervalSince(soloStart)

        // Half a subprocess. The floor of the broken case is `solo - settle`: the batch
        // has been running for `settle` when the read starts, so a `cached()` that has
        // to wait for the actor waits out at least the remainder of the subprocess
        // holding it. Half sits under that floor with room at every host speed the
        // guard below admits, and unlike the old hard-coded 0.2s it means the same
        // thing on a 14-core laptop and a 3-core runner — where 0.2s is a much thinner
        // slice of a much slower subprocess, and went red on a healthy build (#394).
        let bound = solo / 2
        #expect(elapsed < bound, """
            cached() waited \(elapsed)s behind the brew info batch, over the \(bound)s \
            bound derived from a \(solo)s `brew info` on this host
            """)

        // Vacuity guard on this test's own premise, and it has to be an absolute floor
        // now: the old ratio guard (`batch * batchElapsed > 3 * bound`) becomes a
        // tautology once the bound is derived from the same measurement. What actually
        // has to hold is that a subprocess outlasts `settle` by enough to be visible —
        // at `solo == 4 * settle` the broken case still floors at 3x `settle` against a
        // 2x-`settle` bound. Below that the two cases stop being separable and a pass
        // proves nothing.
        #expect(solo > 4 * settle, """
            premise gone: one `brew info` now takes \(solo)s, too close to the \(settle)s \
            the batch is given to settle, so "actor held" and "actor free" are no longer \
            distinguishable here. Re-tune or delete this test.
            """)
    }
}
