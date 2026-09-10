import Testing
import Foundation
import Darwin
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

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// A disk-cached formula must stay instantly readable while a prewarm-sized batch
    /// of uncached `release(...)` calls is in flight. Guards the executor hop in
    /// `brewInfoOffActor`: revert it to a synchronous `Self.brewInfo(name:)` and each
    /// subprocess holds the actor for its whole run, so a `cached(...)` issued beside
    /// one can only return after it exits.
    ///
    /// Ordering, not wall clock. Two bounds were tried and both went red on healthy
    /// builds on the 3-core runner: a fixed 0.2s (#394), then half of one `brew info`
    /// timed after the batch. The second failed 3 times in ~113 CI runs, at 0.53-1.44s.
    /// Instrumented runs of the whole core suite there (2026-09-10, runs 34460475080 and
    /// 34461525444, 32 samples) showed why a bound can't hold. The suite runs ~2,500
    /// tests in parallel in this process, so the cooperative pool is saturated:
    ///   - the old 0.1s settle sleep woke 0.1-6.4s late;
    ///   - the batch's `brew info` started 1.1-9.4s after its tasks were created and
    ///     ran 0.6-7.1s, while the post-batch `solo` ran 0.39-0.99s. The bound was
    ///     measured at a different load from the read it judged, and on a fast
    ///     runner `solo` fell under the old `solo > 4 * settle` guard;
    ///   - a healthy read usually ran inline in ~0.2ms. But in 2 of 32 samples (and 3
    ///     of 6 local full-suite runs) it waited 12-82ms to enter the actor, behind
    ///     batch members whose own entry jobs were still waiting for a pool thread.
    ///     No subprocess was involved. The three CI failures were not captured under
    ///     instrumentation, but that queueing is the only way the instrumented runs
    ///     show a healthy read waiting at all, and pool waits there reached seconds.
    ///
    /// So the read is issued only once every batch member is inside `brew info` at the
    /// same time. A live subprocess means its member has made its actor entry and hopped
    /// off, and none has come back yet, so the actor has nothing queued for the read to
    /// wait behind — nothing except the actor being held, which is the one thing this
    /// is here to catch. The verdict is then an ordering: at least one of those
    /// subprocesses must still be running when `cached()` returns. With the hop
    /// reverted that gate can never be met — each subprocess holds the actor, so at
    /// most one is ever alive (at most 1 of 4 in all 3 hop-reverted samples, run in
    /// their own job on a 3-core runner) — and the test fails and says so.
    ///
    /// Only this process's own children, under names made up here, are looked at, so
    /// the answer doesn't depend on what else the host is running.
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
        // and the ordering check below would then prove nothing.
        #expect(await service.cached(for: cachedName, version: cachedVersion) == seeded,
                "seeded entry must be readable before timing it")

        // A prewarm-sized batch of uncached formulae, each paying a full `brew info`.
        // Up to three batches: the poll below sleeps on the same saturated pool, and one
        // that oversleeps a whole batch must not decide the verdict. A pass needs the
        // gate met once; with the hop reverted it is never met, and that costs three
        // serialized batches before the failure.
        let batch = 4
        let rounds = 3
        var peaks: [Int] = []
        var stillRunningAfterRead: Set<String>?
        var elapsed: TimeInterval = 0
        for round in 0..<rounds {
            let names = (0..<batch).map { "duo-uncached-formula-r\(round)-\($0)" }
            let finished = Counter()
            let inFlight = names.map { name in
                Task {
                    _ = await service.release(for: name, version: "9.9.9", token: nil)
                    finished.increment()
                }
            }
            var peak = 0
            while finished.value < batch {
                let running = Self.runningBrewInfo(named: names)
                peak = max(peak, running.count)
                if running.count == batch {
                    // Nothing suspends between the snapshot and the read, so the
                    // snapshot still describes the actor the read meets.
                    let start = Date()
                    let hit = await service.cached(for: cachedName, version: cachedVersion)
                    elapsed = Date().timeIntervalSince(start)
                    stillRunningAfterRead = Self.runningBrewInfo(named: names)
                    #expect(hit == seeded)
                    break
                }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            for task in inFlight { await task.value }
            peaks.append(peak)
            if stillRunningAfterRead != nil { break }
        }

        guard let stillRunningAfterRead else {
            let most = peaks.max() ?? 0
            let why = switch most {
            case 0: """
                premise gone: no `brew info` was ever seen running, so there is nothing \
                for `cached()` to be kept waiting behind. Re-tune or delete this test.
                """
            case 1: """
                `brew info` was never seen running more than one at a time, which is what \
                a held actor looks like: each subprocess holds it for its whole run, so \
                `cached()` would queue behind every one of them. A batch too short-lived \
                for this poll to catch two together looks the same, so check how long \
                `brew info` takes here before blaming the actor.
                """
            default: """
                the batch overlapped (so the actor is not serializing it) but was never \
                seen all \(batch) at once, so `cached()` was never checked against it.
                """
            }
            Issue.record("\(why) Most seen running at once per round: \(peaks).")
            return
        }
        #expect(!stillRunningAfterRead.isEmpty, """
            cached() returned only after all \(batch) `brew info` subprocesses it was \
            issued beside had exited (\(elapsed)s): something held the actor while they ran
            """)
    }

    /// Which of `names` are in `brew info` right now, read from this process's own
    /// children. `brew` execs into Ruby under the same pid and keeps the formula name as
    /// its last argument, so argv tells the batch apart with no hook in the code under
    /// test. An exited child that hasn't been reaped yet has no argv and doesn't count.
    private static func runningBrewInfo(named names: [String]) -> Set<String> {
        let wanted = Set(names)
        var pids = [pid_t](repeating: 0, count: 4096)
        let listed = proc_listchildpids(
            getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard listed >= 0 else { return [] }
        var running: Set<String> = []
        for pid in pids where pid > 0 {
            if let name = arguments(of: pid)?.last, wanted.contains(name) {
                running.insert(name)
            }
        }
        return running
    }

    /// argv of `pid` from `KERN_PROCARGS2`: an `Int32` argc, the exec path, NUL padding,
    /// then argc NUL-terminated arguments.
    private static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }
        while i < size, buffer[i] == 0 { i += 1 }
        var arguments: [String] = []
        while arguments.count < argc, i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            arguments.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return arguments
    }
}
