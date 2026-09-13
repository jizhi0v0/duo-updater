import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewFormulaService`'s read paths (`outdated()`, and `installedLeaves()`,
/// `outdatedCasks()`, `uncheckedPackages()` via `runReading`) await an `Executor`,
/// which for real runs `brew` through `ChildProcess`. Pinned here:
///
/// 1. The reads do not hold the actor while `brew` runs — the `async let` pair in
///    `installedLeaves()` genuinely overlaps. (They once ran a blocking
///    `Process` sequence straight on the actor, and the pair ran serially.)
/// 2. The real executor's cancellation policy: a cancelled refresh still gets
///    real data, because `AppListModel` writes whatever the reads returned.
///
/// Most tests go through the internal `init(executor:)` seam with a fake executor,
/// per CLAUDE.md "测试不能问宿主" — it answers "no brew" / "throws" / "nonzero exit"
/// on cue, without depending on whether Homebrew is installed. The cancellation
/// test uses the REAL executor (`executor(brewPath:)`) pointed at an invented
/// script, for the same reason.
///
/// Fixture formula/cask names are fictitious (`zzfixture-*`) — never a name that
/// might really be installed — for the same reason.
@Suite struct BrewFormulaServiceTests {

    // MARK: - Overlap (the core regression)

    /// A synchronization gate a fake `Executor` calls into. `arrive()` suspends
    /// until a second caller has also arrived (or `timeout` elapses), and records
    /// the highest number of callers that were ever inside the gate at once.
    ///
    /// It suspends rather than blocking a thread. The `Executor` is `async` since
    /// the real one moved to `ChildProcess`, so the fake awaits here the way the
    /// real one awaits its child — which is also the property being measured: the
    /// actor has to be free while one read waits for the second to start. (The
    /// first version of this gate was built on `NSCondition`, back when the
    /// executor was a synchronous function run on a Dispatch thread.)
    ///
    /// Per CLAUDE.md "并行套件里墙钟上界不成立": this asserts overlap happened
    /// (`observedMaxInFlight`), not how fast it happened. `timeout` only bounds
    /// how long a broken (serialized) run waits before giving up — it is not a
    /// performance assertion, so it is set generously (60s), not tightly.
    final class TwoWayGate: @unchecked Sendable {
        private let lock = NSLock()
        private var arrivedCount = 0
        private var inFlight = 0
        private var maxInFlight = 0
        private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

        func arrive(timeout: Duration = .seconds(60)) async {
            let ticket: Int = lock.withLock {
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                arrivedCount += 1
                return arrivedCount
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        let resumeNow: [CheckedContinuation<Void, Never>] = self.lock.withLock {
                            guard self.arrivedCount < 2 else {
                                defer { self.waiting = [:] }
                                return Array(self.waiting.values) + [continuation]
                            }
                            self.waiting[ticket] = continuation
                            return []
                        }
                        resumeNow.forEach { $0.resume() }
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    let expired = self.lock.withLock { self.waiting.removeValue(forKey: ticket) }
                    expired?.resume()
                }
                await group.next()
                group.cancelAll()
            }
            lock.withLock { inFlight -= 1 }
        }

        var observedMaxInFlight: Int {
            lock.withLock { maxInFlight }
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
            await gate.arrive()
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

    // MARK: - Cancellation (the real executor)

    /// A refresh whose task is cancelled — the popover closed — still reads real
    /// data. `AppListModel.refreshBrewFormulae` does not stop when cancelled; it
    /// writes what the reads returned, so a killed `brew` would replace the Brew
    /// tree with an empty one. The "brew" here is an invented script.
    ///
    /// Mutation: `.terminateChild` in `executor(brewPath:)` → `installedLeaves()`
    /// returns `[]`.
    @Test func aCancelledRefreshStillReadsRealData() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-brew-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let brew = dir.appendingPathComponent("brew")
        try Data("""
            #!/bin/sh
            case "$1" in
              leaves) sleep 0.2; echo zzfixture-alpha ;;
              list) sleep 0.2; echo 'zzfixture-alpha 1.2.3' ;;
            esac
            """.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let path = brew.path
        let service = BrewFormulaService(executor: BrewFormulaService.executor(brewPath: { path }))

        let task = Task { () async throws -> [BrewInstalledFormula] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.installedLeaves()
        }
        let result = try await task.value

        #expect(result.map(\.name) == ["zzfixture-alpha"])
        #expect(result.first?.installedVersion == "1.2.3")
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

    // MARK: - pouredFormula(fromLine:) — the bulk-upgrade progress counter

    /// Measured 2026-09-13, Homebrew 7.0.0: one `brew upgrade --formula xz` printed
    /// both of these. The first is the success summary; the second is the
    /// `brew cleanup` that runs afterwards removing the old keg. Matching any line
    /// that contains `/Cellar/<name>/` counted xz twice, and because the counter is
    /// clamped to the total a bulk run read n/n before it had finished.
    /// (Pure string parsing — the real paths here never reach the filesystem.)
    @Test func aSuccessfulUpgradeCountsOnceDespiteTheCleanupLine() {
        let output = [
            "🍺  /opt/homebrew/Cellar/xz/5.8.4: 96 files, 2.7MB",
            "Removing: /opt/homebrew/Cellar/xz/5.8.3... (96 files, 2.7MB)",
        ]
        #expect(output.compactMap(BrewFormulaService.pouredFormula(fromLine:)) == ["xz"])
    }

    /// Other brew lines that carry a keg path and a size, none of them a success.
    @Test(arguments: [
        "Removing: /opt/homebrew/Cellar/zzfixture-alpha/1.0... (96 files, 2.7MB)",
        "Would remove: /opt/homebrew/Cellar/zzfixture-alpha/1.0 (96 files, 2.7MB)",
        "Uninstalling /opt/homebrew/Cellar/zzfixture-alpha/1.0... (96 files, 2.7MB)",
        "Linking /opt/homebrew/Cellar/zzfixture-alpha/1.0... 12 symlinks created.",
    ])
    func nonSuccessCellarLinesAreNotCounted(line: String) {
        #expect(BrewFormulaService.pouredFormula(fromLine: line) == nil)
    }

    /// The badge is `HOMEBREW_INSTALL_BADGE` (any text) and absent under
    /// `HOMEBREW_NO_EMOJI`, so the success line must be recognized without it; a
    /// single-file keg's `abv` has no `N files, ` part; a source build appends
    /// `, built in …`.
    @Test(arguments: [
        ("🍺  /opt/homebrew/Cellar/zzfixture-alpha/1.0: 96 files, 2.7MB", "zzfixture-alpha"),
        ("/opt/homebrew/Cellar/zzfixture-alpha/1.0: 96 files, 2.7MB", "zzfixture-alpha"),
        ("DONE  /usr/local/Cellar/zzfixture-beta@3/3.1_1: 3,123 files, 65MB, built in 2 minutes 3 seconds", "zzfixture-beta@3"),
        ("🍺  /opt/homebrew/Cellar/zzfixture-gamma/0.2: 512B", "zzfixture-gamma"),
    ])
    func successLinesAreRecognizedWhateverTheBadge(line: String, name: String) {
        #expect(BrewFormulaService.pouredFormula(fromLine: line) == name)
    }
}
