import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewFormulaService`'s three read paths (`outdated()`, `installedLeaves()` via
/// `runReading`, `outdatedCasks()` via `runReading`) used to run the blocking
/// `Process.run()` → `readDataToEndOfFile()` → `waitUntilExit()` sequence directly
/// on the actor. That has two consequences pinned here:
///
/// 1. It violates CLAUDE.md "别在协作池上做阻塞调用" — a synchronous call on the
///    actor occupies one of the cooperative pool's few threads for the whole
///    subprocess.
/// 2. It defeated `installedLeaves()`'s `async let` pair: with no suspension point
///    inside `runReading`, the actor could not even start the second read until the
///    first one's subprocess had exited, so the two `brew` calls always ran
///    serially despite the "run them concurrently" comment.
///
/// All tests here go through the internal `init(executor:)` seam instead of a real
/// `brew` subprocess, per CLAUDE.md "测试不能问宿主" — a fake executor answers "no
/// brew" / "throws" / "nonzero exit" on cue, deterministically, without depending
/// on whether Homebrew happens to be installed on whatever machine runs this.
///
/// Fixture formula/cask names are fictitious (`zzfixture-*`) — never a name that
/// might really be installed — for the same reason.
@Suite struct BrewFormulaServiceTests {

    // MARK: - Overlap (the core regression)

    /// A synchronization gate a fake `Executor` calls into. `arrive()` blocks the
    /// calling thread until a second caller has also arrived (or `timeout`
    /// elapses), and records the highest number of callers that were ever inside
    /// the gate at once. This is deliberately built on locks, not Swift
    /// concurrency: the `Executor` closure is a plain synchronous function (it
    /// can't `await`), and the whole point is to observe REAL thread-level
    /// overlap of the two `brew` calls, not cooperative scheduling.
    ///
    /// Per CLAUDE.md "并行套件里墙钟上界不成立": this asserts overlap happened
    /// (`observedMaxInFlight`), not how fast it happened. `timeout` only bounds
    /// how long a broken (serialized) run waits before giving up — it is not a
    /// performance assertion, so it is set generously (60s), not tightly.
    ///
    /// On the healthy path the second caller arrives almost immediately (both
    /// `async let` child tasks start right away, and `arrive()` returns the
    /// moment the second one calls in), so this test does not normally pay
    /// anywhere near the full timeout. But a passing run CAN legitimately take
    /// seconds to get there: the second child task still needs a cooperative-pool
    /// thread before it can even reach its own call into the gate, and this repo
    /// has measured 0.5-6.4s of pool-admission / Dispatch wait on a 3-core CI
    /// runner when ~2550 tests are running concurrently in one process (see
    /// CLAUDE.md "并行套件里墙钟上界不成立"). A short timeout would read that
    /// scheduling delay as "never overlapped" and fail a correct implementation.
    final class TwoWayGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var arrivedCount = 0
        private var inFlight = 0
        private var maxInFlight = 0

        func arrive(timeout: TimeInterval = 60) {
            condition.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            arrivedCount += 1
            condition.broadcast()
            let deadline = Date().addingTimeInterval(timeout)
            while arrivedCount < 2 {
                if !condition.wait(until: deadline) { break }
            }
            inFlight -= 1
            condition.unlock()
        }

        var observedMaxInFlight: Int {
            condition.lock()
            defer { condition.unlock() }
            return maxInFlight
        }
    }

    /// Canned stdout for the two `installedLeaves()` subcommands.
    private static func leavesOutput() -> Data { Data("zzfixture-alpha\nzzfixture-beta\n".utf8) }
    private static func versionsOutput() -> Data {
        Data("zzfixture-alpha 1.0.0\nzzfixture-beta 2.0.0\n".utf8)
    }

    @Test func installedLeavesReadsGenuinelyOverlap() async throws {
        let gate = TwoWayGate()
        let service = BrewFormulaService(executor: { arguments in
            gate.arrive()
            if arguments == ["leaves"] {
                return (0, Self.leavesOutput())
            } else if arguments == ["list", "--formula", "--versions"] {
                return (0, Self.versionsOutput())
            }
            Issue.record("unexpected arguments: \(arguments)")
            return (1, Data())
        })

        let result = try await service.installedLeaves()

        // The two subprocess calls were both in flight at the same time — the
        // thing that was NOT true before the actor hop, when the second could not
        // start until the first's `Process` had already exited.
        #expect(gate.observedMaxInFlight == 2)

        #expect(result.map(\.name) == ["zzfixture-alpha", "zzfixture-beta"])
        #expect(result.first { $0.name == "zzfixture-alpha" }?.installedVersion == "1.0.0")
        #expect(result.first { $0.name == "zzfixture-beta" }?.installedVersion == "2.0.0")
        #expect(result.allSatisfy { $0.availableVersion == nil })
    }

    // MARK: - Behavior preserved: outdated()

    @Test func outdatedReturnsEmptyWhenBrewIsAbsent() async throws {
        let service = BrewFormulaService(executor: { _ in nil })
        let result = try await service.outdated()
        #expect(result.isEmpty)
    }

    private struct FakeSpawnFailure: Error {}

    /// "process.run() 抛错 → 现在是向上抛(别吞掉)" — `outdated()` must propagate,
    /// not swallow, an executor throw.
    @Test func outdatedPropagatesASpawnFailure() async throws {
        let service = BrewFormulaService(executor: { _ in throw FakeSpawnFailure() })
        await #expect(throws: FakeSpawnFailure.self) {
            _ = try await service.outdated()
        }
    }

    @Test func outdatedThrowsFailedOnNonzeroExit() async throws {
        let service = BrewFormulaService(executor: { _ in
            (7, Data("Error: zzfixture-broken: no such tap".utf8))
        })
        do {
            _ = try await service.outdated()
            Issue.record("expected outdated() to throw BrewError.failed")
        } catch BrewFormulaService.BrewError.failed(let code, let output) {
            #expect(code == 7)
            #expect(output.contains("zzfixture-broken"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func outdatedParsesASuccessfulResponse() async throws {
        let payload = Data("""
        {"formulae":[{"name":"zzfixture-alpha","installed_versions":["1.0.0"],
         "current_version":"1.1.0","pinned":false}],"casks":[]}
        """.utf8)
        let service = BrewFormulaService(executor: { arguments in
            #expect(arguments == ["outdated", "--formula", "--json=v2"])
            return (0, payload)
        })
        let result = try await service.outdated()
        #expect(result.count == 1)
        #expect(result.first?.name == "zzfixture-alpha")
        #expect(result.first?.installedVersion == "1.0.0")
        #expect(result.first?.currentVersion == "1.1.0")
    }

    // MARK: - Behavior preserved: runReading (via installedLeaves / outdatedCasks)

    @Test func installedLeavesReturnsEmptyWhenBrewIsAbsent() async throws {
        let service = BrewFormulaService(executor: { _ in nil })
        let result = try await service.installedLeaves()
        #expect(result.isEmpty)
    }

    /// `runReading` swallows an executor throw into `""` — unlike `outdated()`,
    /// which must propagate it. A thrown spawn failure on either subcommand must
    /// not surface as a thrown error from `installedLeaves()`.
    @Test func installedLeavesSwallowsASpawnFailure() async throws {
        let service = BrewFormulaService(executor: { _ in throw FakeSpawnFailure() })
        let result = try await service.installedLeaves()
        #expect(result.isEmpty)
    }

    @Test func installedLeavesTreatsNonzeroExitAsEmpty() async throws {
        let service = BrewFormulaService(executor: { _ in (1, Data("boom".utf8)) })
        let result = try await service.installedLeaves()
        #expect(result.isEmpty)
    }

    @Test func outdatedCasksReturnsEmptyWhenBrewIsAbsent() async throws {
        let service = BrewFormulaService(executor: { _ in nil })
        let result = try await service.outdatedCasks()
        #expect(result.isEmpty)
    }

    @Test func outdatedCasksSwallowsASpawnFailure() async throws {
        let service = BrewFormulaService(executor: { _ in throw FakeSpawnFailure() })
        let result = try await service.outdatedCasks()
        #expect(result.isEmpty)
    }

    @Test func outdatedCasksTreatsNonzeroExitAsEmpty() async throws {
        let service = BrewFormulaService(executor: { _ in (1, Data("boom".utf8)) })
        let result = try await service.outdatedCasks()
        #expect(result.isEmpty)
    }

    /// End-to-end wiring for the cask path: JSON in, filtered-by-`installsAnApp`
    /// result out. `zzfixture-cli` has no staged `.app`/`.pkg` anywhere real (it
    /// doesn't exist), so it passes the filter; the parser/filter behavior itself
    /// is covered in depth by `BrewOutdatedCaskTests`.
    ///
    /// The fake `Executor` above only replaces the `brew` subprocess half of
    /// `outdatedCasks()` — the filter half, `installsAnApp(caskToken:)`, reads the
    /// REAL Caskroom via `BrewLocalInventory.defaultCaskroomPaths` directly off
    /// disk, with no executor seam. So an invented-sounding fixture name is not
    /// enough by itself (CLAUDE.md "测试不能问宿主": a name that merely LOOKS
    /// fictitious but happens to collide with something real on some machine is
    /// exactly the "implicitly asking the host" shape). Assert up front, as a gate
    /// that fails loudly rather than a comment that can rot, that this name is not
    /// staged in any real Caskroom this test would actually read.
    @Test func outdatedCasksParsesAndFiltersASuccessfulResponse() async throws {
        for root in BrewLocalInventory.defaultCaskroomPaths {
            #expect(!FileManager.default.fileExists(atPath: root + "/zzfixture-cli"))
        }

        let payload = Data("""
        {"formulae":[],"casks":[
          {"name":"zzfixture-cli","installed_versions":["0.1.0"],
           "current_version":"0.2.0","pinned":false,"pinned_version":null}
        ]}
        """.utf8)
        let service = BrewFormulaService(executor: { arguments in
            #expect(arguments == ["outdated", "--cask", "--json=v2"])
            return (0, payload)
        })
        let result = try await service.outdatedCasks()
        #expect(result.count == 1)
        #expect(result.first?.name == "zzfixture-cli")
        #expect(result.first?.kind == .cask)
    }
}
