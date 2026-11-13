import Foundation
import Testing
@testable import DuoUpdaterCore

/// Characterizes the current automatic-install policy with a fake date, then
/// exercises production download/apply and quit/commit boundaries on scratch
/// bundles. This does not run AppListModel: it owns the error-to-ledger mapping,
/// clean-check retention keys, live permissions and the decision to start a pass.
/// Unclassified recordFailure calls below pin legacy ledger compatibility;
/// terminal HTTP and checksum cases also exercise the classified production
/// capture wrappers now used around AppListModel's coordinator call.
struct HTTPAutomaticUpdateSimulationTests {
    private typealias Policy = RunningAppAutoUpdate
    private typealias Counter = RunningAppQuitBeforeApplyTests.Counter
    private typealias Signal = InstallCommitTests.Signal
    private let firstFailure = Date(timeIntervalSince1970: 2_000_000_000)
    private let installKey = "com.example.http-simulation:/scratch/Target.app"

    @Test func legacyFiveMinuteChecksDoNotOverrideTheDayLongFailureBackoff() throws {
        // Literal expectations pin production defaults. No developer-threshold
        // override or writes to UserDefaults are needed to advance this clock.
        #expect(Policy.retryBackoff == 86_400)
        #expect(Policy.maxFailures == 3)
        var ledger = Policy.Ledger()
        let initial = ledger.observe(installKey, version: "2.0", now: firstFailure)
        #expect(Policy.decide(entry: initial, now: firstFailure) == .quitAndUpdate)

        // The caller records an install error. HTTP classification happens
        // outside this API and is deliberately not reproduced in this test.
        ledger.recordFailure(installKey, now: firstFailure)
        var entry = try #require(ledger.entries[installKey])
        #expect(entry.failures == 1)
        #expect(!entry.gaveUp)
        #expect(entry.retryAfter == firstFailure.addingTimeInterval(86_400))
        #expect(entry.lastQuit == nil)
        #expect(CheckSchedule.nextWait(
            now: firstFailure, lastCheck: firstFailure, interval: 300,
            isFirstCheck: false, hasResults: true) == 300)

        // A process restart preserves the backoff. A cold launch may check
        // immediately; an ordinary five-minute tick may check at +300s.
        ledger = try restored(ledger)
        let fiveMinutesLater = firstFailure.addingTimeInterval(300)
        #expect(CheckSchedule.nextWait(
            now: fiveMinutesLater, lastCheck: firstFailure, interval: 300,
            isFirstCheck: false, hasResults: true) == 0)
        #expect(CheckSchedule.nextWait(
            now: fiveMinutesLater, lastCheck: fiveMinutesLater, interval: 300,
            isFirstCheck: true, hasResults: false) == 0)
        entry = ledger.observe(installKey, version: "2.0", now: fiveMinutesLater)
        #expect(Policy.decide(entry: entry, now: fiveMinutesLater) == .wait(.retryLater))
        #expect(entry.failures == 1)

        let justBeforeRetry = firstFailure.addingTimeInterval(86_399)
        #expect(Policy.decide(entry: entry, now: justBeforeRetry) == .wait(.retryLater))
        let secondAttempt = firstFailure.addingTimeInterval(86_400)
        #expect(Policy.decide(entry: entry, now: secondAttempt) == .quitAndUpdate)
        ledger.recordFailure(installKey, now: secondAttempt)
        entry = try #require(ledger.entries[installKey])
        #expect(entry.failures == 2)
        #expect(!entry.gaveUp)
        #expect(entry.retryAfter == firstFailure.addingTimeInterval(172_800))
        #expect(Policy.decide(entry: entry, now: secondAttempt.addingTimeInterval(300)) == .wait(.retryLater))

        let thirdAttempt = firstFailure.addingTimeInterval(172_800)
        #expect(Policy.decide(entry: entry, now: thirdAttempt) == .quitAndUpdate)
        ledger.recordFailure(installKey, now: thirdAttempt)
        ledger = try restored(ledger)
        entry = try #require(ledger.entries[installKey])
        #expect(entry.failures == 3)
        #expect(entry.gaveUp)
        #expect(entry.retryAfter == firstFailure.addingTimeInterval(259_200))
        #expect(Policy.decide(entry: entry, now: thirdAttempt) == .wait(.gaveUp))
        #expect(Policy.decide(entry: entry, now: firstFailure.addingTimeInterval(345_600)) == .wait(.gaveUp))
    }

    /// The implementation compares offered display-version strings, not version
    /// ordering. Even a changed, lower string clears the limit. This is current
    /// behavior to audit, not a claim that a downgrade should reset failures.
    @Test(arguments: ["2.1", "1.9"])
    func anyChangedOfferedVersionResetsLegacyFailuresButKeepsTheInstallCooldown(offered: String) throws {
        var ledger = Policy.Ledger()
        _ = ledger.observe(installKey, version: "2.0", now: firstFailure)
        ledger.recordQuit(installKey, now: firstFailure)
        for day in 0..<3 {
            ledger.recordFailure(installKey, now: firstFailure.addingTimeInterval(Double(day) * 86_400))
        }
        let lastFailure = firstFailure.addingTimeInterval(172_800)
        let newOfferDate = lastFailure.addingTimeInterval(300)
        let sameOffer = ledger.observe(installKey, version: "2.0", now: newOfferDate)
        #expect(sameOffer.failures == 3)
        #expect(sameOffer.gaveUp)

        let changed = ledger.observe(installKey, version: offered, now: newOfferDate)
        #expect(changed.version == offered)
        #expect(changed.failures == 0)
        #expect(!changed.gaveUp)
        #expect(changed.behindSince == firstFailure)
        #expect(changed.lastQuit == firstFailure)
        #expect(changed.retryAfter == lastFailure.addingTimeInterval(86_400))
        ledger = try restored(ledger)
        let afterRestart = try #require(ledger.entries[installKey])
        #expect(afterRestart == changed)
        #expect(Policy.decide(entry: afterRestart, now: newOfferDate) == .wait(.retryLater))
        #expect(Policy.decide(entry: afterRestart, now: lastFailure.addingTimeInterval(86_400)) == .quitAndUpdate)
    }

    @Test func callerSuppliedRetentionKeysCleanCaughtUpAndMissingCopiesWithoutResettingOtherInstalls() throws {
        let otherCopy = "com.example.http-simulation:/scratch/Other/Target.app"
        let caughtUp = "caller-says-up-to-date"
        let missing = "caller-says-no-longer-installed"
        var ledger = Policy.Ledger()
        for key in [installKey, otherCopy, caughtUp, missing] {
            _ = ledger.observe(key, version: "2.0", now: firstFailure)
        }
        ledger.recordFailure(installKey, now: firstFailure)
        ledger.recordQuitRefused(caughtUp, now: firstFailure)
        ledger.recordFailure(missing, now: firstFailure)
        let failedCheckHistory = try #require(ledger.entries[installKey])
        let otherHistory = try #require(ledger.entries[otherCopy])
        #expect(Policy.decide(entry: otherHistory, now: firstFailure) == .quitAndUpdate)

        // These are explicitly supplied keys, as retain requires. This does not
        // exercise AppListModel's scan/status-to-retention-key selection.
        ledger.retain(keys: [installKey, otherCopy])
        ledger = try restored(ledger)
        #expect(Set(ledger.entries.keys) == Set([installKey, otherCopy]))
        #expect(ledger.entries[installKey] == failedCheckHistory)
        #expect(ledger.entries[otherCopy] == otherHistory)
        #expect(Policy.decide(entry: failedCheckHistory, now: firstFailure.addingTimeInterval(300)) == .wait(.retryLater))

        // Once the caller removed a caught-up copy, its next update has no old
        // give-up/backoff. The other installed copy's failure remains intact.
        let next = ledger.observe(caughtUp, version: "3.0", now: firstFailure.addingTimeInterval(300))
        #expect(next.failures == 0)
        #expect(next.retryAfter == nil)
        #expect(!next.gaveUp)
        #expect(Policy.decide(entry: next, now: firstFailure.addingTimeInterval(300)) == .quitAndUpdate)
        #expect(ledger.entries[installKey] == failedCheckHistory)
    }

    /// Production coordinator, injected terminal download errors. This covers
    /// the download-to-apply boundary, not URLSession's per-request retry loop
    /// or AppListModel's decision to record these errors in its ledger.
    @Test(arguments: [401, 403, 404, 408, 410, 429, 500, 501, 502, 503, 504, 505])
    func terminalHTTPDownloadFailureNeverReachesApplyOrQuit(status: Int) async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let downloads = Counter(), applies = Counter(), quits = Counter(), releases = Counter()
        let failureAttempt = AutomaticUpdateFailurePolicy.Attempt()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        let coordinator = InstallCoordinator(
            permits: InstallPermits(downloads: 1, applies: 1), runningProcesses: { [] })
        await AutomaticUpdateFailurePolicy.$attempt.withValue(failureAttempt) {
            await AutomaticInstall.$active.withValue(true) {
                await AutomaticInstall.$permission.withValue({ true }) {
                    await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                        do {
                            _ = try await AutomaticUpdateFailurePolicy.capturing {
                                try await coordinator.fetchThenSwap(
                                    scratch.result(), spaceToApply: 0,
                                    progress: AutomaticUpdateFailurePolicy.recordingProgress { _ in },
                                    releaseAfterDownload: AutomaticUpdateFailurePolicy.afterDownload { releases.increment() },
                                    download: { _, _ in
                                        downloads.increment()
                                        throw Downloader.DownloadError.httpStatus(status)
                                    },
                                    apply: { _, _, _ in
                                        applies.increment()
                                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                                    })
                            }
                            Issue.record("A terminal HTTP download failure unexpectedly succeeded")
                        } catch Downloader.DownloadError.httpStatus(let actual) {
                            #expect(actual == status)
                        } catch {
                            Issue.record("Expected HTTP \(status), got \(error)")
                        }
                    }
                }
            }
        }
        #expect(downloads.value == 1)
        #expect(applies.value == 0)
        #expect(quits.value == 0)
        #expect(releases.value == 0)
        #expect(plan.pending)
        #expect(try scratch.targetBytes() == Data("old".utf8))
        let capture = try #require(failureAttempt.capture)
        if case .httpStatus(let actual) = capture.error as? Downloader.DownloadError {
            #expect(actual == status)
        } else {
            Issue.record("The capture lost the concrete HTTP status error")
        }
        #expect(capture.evidence.stage == .downloading(fraction: 0))
        #expect(!capture.evidence.acquisitionFinished)
        let failure = try #require(failureAttempt.failure(or: "missing failure"))
        let recoverable = [408, 429, 500, 502, 503, 504].contains(status)
        #expect(failure.disposition == (recoverable ? .retryAcquisition : .pauseVersion))
        var ledger = Policy.Ledger()
        _ = ledger.observe(installKey, version: "2.0", now: firstFailure)
        ledger.recordFailure(installKey, failure: failure, now: firstFailure)
        let entry = try #require(ledger.entries[installKey])
        #expect(entry.failures == 0)
        #expect(entry.acquisitionFailures == (recoverable ? 1 : nil))
        let atNextDay = Policy.decide(entry: entry, now: firstFailure.addingTimeInterval(86_400))
        #expect(atNextDay == (recoverable ? .quitAndUpdate : .wait(.pausedFailure(failure.reason))))
    }

    /// Actual VendorInstaller.apply, with a digest mismatch caught before
    /// extraction. Moving its quit ahead of verification would fail this test.
    @Test func vendorChecksumFailureLeavesThePlannedQuitPending() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let archive = scratch.root.appendingPathComponent("download.zip")
        try Data("an untrusted download".utf8).write(to: archive)
        let quits = Counter()
        let failureAttempt = AutomaticUpdateFailurePolicy.Attempt()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        let stages = RunningAppQuitBeforeApplyTests.Log()
        let result = scratch.result(expectedSHA256: String(repeating: "0", count: 64))
        let download = DownloadedUpdate(archiveURL: archive, bytesDownloaded: 21, workDir: scratch.root)
        await AutomaticUpdateFailurePolicy.$attempt.withValue(failureAttempt) {
            await AutomaticInstall.$active.withValue(true) {
                await AutomaticInstall.$permission.withValue({ true }) {
                    await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                        do {
                            try await AutomaticUpdateFailurePolicy.capturing {
                                try await VendorInstaller().apply(
                                    result, download: download, digestOnlyAllowed: false,
                                    onStage: AutomaticUpdateFailurePolicy.recordingProgress { stage in
                                        if case .verifyingSignature = stage { stages.append("verifyingSignature") }
                                        if case .installing = stage { stages.append("installing") }
                                    })
                            }
                            Issue.record("An incorrect published checksum unexpectedly passed")
                        } catch VendorInstaller.InstallError.checksumMismatch {
                            // Assert this specific gate was reached, rather than
                            // accepting an unrelated early refusal as evidence.
                        } catch {
                            Issue.record("Expected checksumMismatch, got \(error)")
                        }
                    }
                }
            }
        }
        #expect(stages.value == ["verifyingSignature"])
        #expect(quits.value == 0)
        #expect(plan.pending)
        #expect(try scratch.targetBytes() == Data("old".utf8))
        let capture = try #require(failureAttempt.capture)
        #expect(capture.evidence.stage == .verifyingSignature)
        #expect(capture.evidence.advancedPastAcquisition)
        let failure = try #require(failureAttempt.failure(or: "missing failure"))
        #expect(failure.disposition == .pauseVersion)
    }

    @Test func revokedPermissionAtAnEligibleRetryStopsBeforeQuitAndCommit() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try assertRetryEligible()
        let quits = Counter(), commits = Counter(), checks = Counter()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ checks.increment(); return false }) {
                await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                    await #expect(throws: AutomaticInstall.Deferred.self) {
                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                        _ = try await InstallCommit.run("ZZFixture-http-revoked-\(UUID().uuidString)") {
                            commits.increment()
                            return try await InPlaceSwap.replace(newApp: scratch.incoming, over: scratch.target)
                        }
                    }
                }
            }
        }
        #expect(checks.value == 1)
        #expect(quits.value == 0)
        #expect(commits.value == 0)
        #expect(plan.pending)
        #expect(try scratch.targetBytes() == Data("old".utf8))
    }

    @Test func aRealTaskCancellationAtAnEligibleRetryStopsBeforeQuitAndCommit() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try assertRetryEligible()
        let release = Signal()
        let quits = Counter(), commits = Counter(), checks = Counter()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        let task = Task {
            // Keep the attempt before its permission checkpoint until its own
            // Task has received cancel(). There is no wall-clock sleep.
            await release.wait()
            #expect(Task.isCancelled)
            try await AutomaticInstall.$active.withValue(true) {
                // AppListModel's permission includes !Task.isCancelled. The
                // other live app permissions are intentionally out of scope.
                try await AutomaticInstall.$permission.withValue({
                    checks.increment()
                    return !Task.isCancelled
                }) {
                    try await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                        _ = try await InstallCommit.run("ZZFixture-http-cancelled-\(UUID().uuidString)") {
                            commits.increment()
                            return try await InPlaceSwap.replace(newApp: scratch.incoming, over: scratch.target)
                        }
                    }
                }
            }
        }
        task.cancel()
        release.fire()
        await #expect(throws: AutomaticInstall.Deferred.self) { try await task.value }
        #expect(checks.value == 1)
        #expect(quits.value == 0)
        #expect(commits.value == 0)
        #expect(plan.pending)
        #expect(try scratch.targetBytes() == Data("old".utf8))
    }

    @Test func refusedQuitStopsBeforeCommitAndTheLedgerCanPersistItsGiveUp() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let requests = Counter(), commits = Counter()
        let plan = AutomaticInstall.QuitBeforeApply {
            requests.increment()
            throw AutomaticInstall.Deferred("The simulated app refused the normal quit")
        }
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                    await #expect(throws: AutomaticInstall.Deferred.self) {
                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                        _ = try await InstallCommit.run("ZZFixture-http-refused-\(UUID().uuidString)") {
                            commits.increment()
                            return try await InPlaceSwap.replace(newApp: scratch.incoming, over: scratch.target)
                        }
                    }
                }
            }
        }
        #expect(requests.value == 1)
        #expect(commits.value == 0)
        #expect(!plan.pending)
        #expect(try scratch.targetBytes() == Data("old".utf8))

        // The caller supplies this mutation; this is not a test of
        // AppListModel.quitForSwap's mapping of its live quit result.
        var ledger = Policy.Ledger()
        _ = ledger.observe(installKey, version: "2.0", now: firstFailure)
        ledger.recordQuitRefused(installKey, now: firstFailure)
        ledger = try restored(ledger)
        let refused = try #require(ledger.entries[installKey])
        #expect(refused.failures == 0)
        #expect(refused.gaveUp)
        #expect(refused.retryAfter == firstFailure.addingTimeInterval(86_400))
        #expect(Policy.decide(entry: refused, now: firstFailure.addingTimeInterval(86_400)) == .wait(.gaveUp))
    }

    /// At the deadline the ledger permits another attempt. A quit is then
    /// possible at the real pre-swap hook, provided its permission still holds.
    /// The entire exchange here is confined to this test's scratch directory.
    @Test func anEligibleRetryCanQuitOnceAndCommitAScratchExchange() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try assertRetryEligible()
        let quits = Counter(), commits = Counter()
        let plan = AutomaticInstall.QuitBeforeApply { quits.increment() }
        try await AutomaticInstall.$active.withValue(true) {
            try await AutomaticInstall.$permission.withValue({ true }) {
                try await AutomaticInstall.$commitPermission.withValue({ true }) {
                    try await AutomaticInstall.$quitBeforeApply.withValue(plan) {
                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                        try await AutomaticInstall.quitPlannedApp(before: scratch.target)
                        _ = try await InstallCommit.run("ZZFixture-http-allowed-\(UUID().uuidString)") {
                            commits.increment()
                            return try await InPlaceSwap.replace(newApp: scratch.incoming, over: scratch.target)
                        }
                    }
                }
            }
        }
        #expect(quits.value == 1)
        #expect(commits.value == 1)
        #expect(!plan.pending)
        #expect(try scratch.targetBytes() == Data("new".utf8))
    }

    private func restored(_ ledger: Policy.Ledger) throws -> Policy.Ledger {
        try JSONDecoder().decode(Policy.Ledger.self, from: JSONEncoder().encode(ledger))
    }

    private func assertRetryEligible() throws {
        var ledger = Policy.Ledger()
        _ = ledger.observe(installKey, version: "2.0", now: firstFailure)
        let attempt = AutomaticUpdateFailurePolicy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        attempt.record(Downloader.DownloadError.httpStatus(503))
        ledger.recordFailure(installKey, failure: try #require(attempt.failure(or: "missing")), now: firstFailure)
        let entry = try #require(ledger.entries[installKey])
        #expect(Policy.decide(entry: entry, now: firstFailure.addingTimeInterval(86_400)) == .quitAndUpdate)
    }

    private struct Scratch: Sendable {
        let root: URL
        let target: URL
        let incoming: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZZFixture-http-automatic-\(UUID().uuidString)", isDirectory: true)
            target = root.appendingPathComponent("Target.app", isDirectory: true)
            incoming = root.appendingPathComponent("Incoming.app", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
                try Data("old".utf8).write(to: target.appendingPathComponent("payload"))
                try Data("new".utf8).write(to: incoming.appendingPathComponent("payload"))
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func result(expectedSHA256: String? = nil) -> UpdateResult {
            UpdateResult(
                app: InstalledApp(
                    name: "ZZHTTPSimulation", bundleID: "com.example.http-simulation",
                    shortVersion: "1.0", buildVersion: "1", path: target,
                    isMASApp: false, sparkleFeedURL: nil),
                remote: RemoteVersion(
                    shortVersion: "2.0", version: "2",
                    downloadURL: URL(string: "https://http-simulation.invalid/download.zip")!,
                    sourceName: "Vendor", vendorInstallerKind: .zip, expectedSHA256: expectedSHA256),
                status: .updateAvailable(latest: "2.0"))
        }

        func targetBytes() throws -> Data { try Data(contentsOf: target.appendingPathComponent("payload")) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
