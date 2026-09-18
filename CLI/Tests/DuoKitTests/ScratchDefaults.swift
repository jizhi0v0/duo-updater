import Foundation
import Testing

/// A throwaway preferences suite, so tests that write settings never touch the
/// real `com.duoupdater.app` domain.
///
/// Every call gets a fresh `com.duoupdater.tests.<UUID>` suite. The suite is
/// registered with the enclosing `.scratchPreferences` scope, which removes it
/// when the test ends — including when the test throws, records an issue, or
/// returns early.
func scratchDefaults() -> UserDefaults {
    let suite = "com.duoupdater.tests.\(UUID().uuidString)"
    ScratchSuites.register(suite)
    return UserDefaults(suiteName: suite)!
}

/// Removes a scratch suite: empties the domain, then unlinks its plist.
///
/// Neither half is enough on its own, and on this OS the pair still isn't.
/// Measured 2026-09-18 on macOS 27.0 (Darwin 27.0.0):
///
///   - `removePersistentDomain(forName:)` alone empties the domain but leaves a
///     42-byte empty plist on disk, so the file count grows by one per test
///     anyway — the leak this file exists to stop.
///   - Unlinking alone loses a race. cfprefsd keeps its own cached copy of every
///     domain the process touched and writes it back on its own schedule. Over
///     50 fresh suites per recipe, counted after the process exited, the file was
///     back in 38–39 of 50.
///   - Both together, plus the exit backstop below, still left 0, 7, 14, 0 and 14
///     files behind over five runs of the two producing suites. cfprefsd's
///     write-back can land well after the process is gone — one run's leftovers
///     were observed appearing during the *next* run.
///
/// Emptying first is what makes the leftovers harmless when they do appear: the
/// write-back can only restore an empty domain, never test data — which is the
/// most an in-process cleanup can promise. Collecting the stragglers has to
/// happen outside the test process; an in-process unlink cannot be the last word
/// on the file.
///
/// There is deliberately no unit test pinning any of this. The write-back happens
/// after the test process exits, so an in-process `fileExists(atPath:)` reports
/// "gone" for every recipe above, including the broken ones — such a test would
/// pass while the leak continued. The check that discriminates is counting
/// `~/Library/Preferences/com.duoupdater.tests.*.plist` across a full `make test`.
func removeScratchSuite(_ suite: String) {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    CFPreferencesAppSynchronize(suite as CFString)
    try? FileManager.default.removeItem(atPath: scratchSuitePath(suite))
}

/// Where `cfprefsd` keeps a scratch suite's plist.
func scratchSuitePath(_ suite: String) -> String {
    NSHomeDirectory() + "/Library/Preferences/\(suite).plist"
}

/// The suites created by one test.
///
/// Held in a task local rather than one global list because suites run in
/// parallel: a shared list would let one test's cleanup delete a suite another
/// test is still using.
enum ScratchSuites {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []

        func add(_ name: String) {
            lock.lock()
            names.append(name)
            lock.unlock()
        }

        func drain() -> [String] {
            lock.lock()
            let taken = names
            names = []
            lock.unlock()
            return taken
        }
    }

    @TaskLocal private static var box: Box?

    /// Every suite this process created, so the exit backstop can unlink any
    /// file cfprefsd wrote back after a test's own cleanup ran.
    private static let allLock = NSLock()
    nonisolated(unsafe) private static var all: [String] = []

    private static let installExitBackstop: Void = {
        atexit { ScratchSuites.unlinkEverything() }
    }()

    /// Unlinks every scratch plist at process exit. The per-test cleanup already
    /// emptied these domains, so this only removes files cfprefsd recreated.
    static func unlinkEverything() {
        allLock.lock()
        let names = all
        allLock.unlock()
        for name in names {
            // Force cfprefsd's pending write for the domain to land first, so
            // the unlink is the last word rather than losing a race with it.
            CFPreferencesAppSynchronize(name as CFString)
            try? FileManager.default.removeItem(atPath: scratchSuitePath(name))
        }
    }

    static func register(_ suite: String) {
        _ = installExitBackstop
        allLock.lock()
        all.append(suite)
        allLock.unlock()
        guard let box = box else {
            // No enclosing scope — the suite would outlive the run, which is the
            // leak this file exists to stop. Fail loudly instead of leaking
            // quietly: add `.scratchPreferences` to the `@Suite` attribute.
            Issue.record("""
                scratchDefaults() was called outside a .scratchPreferences scope, \
                so \(suite) would be left behind in ~/Library/Preferences. \
                Add .scratchPreferences to the enclosing @Suite.
                """)
            return
        }
        box.add(suite)
    }

    /// Runs `body` with a fresh registry, then removes whatever it collected.
    static func withScope(_ body: () async throws -> Void) async rethrows {
        let box = Box()
        defer { box.drain().forEach(removeScratchSuite) }
        try await $box.withValue(box) { try await body() }
    }
}

/// Removes every scratch preferences suite a test created, however the test ends.
///
/// Applied to a `@Suite`, it wraps each of that suite's tests.
struct ScratchPreferencesTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await ScratchSuites.withScope(function)
    }
}

extension Trait where Self == ScratchPreferencesTrait {
    /// See `ScratchPreferencesTrait`.
    static var scratchPreferences: Self { Self() }
}
