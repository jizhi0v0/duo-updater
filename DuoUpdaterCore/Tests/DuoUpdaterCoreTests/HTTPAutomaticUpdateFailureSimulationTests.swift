import Foundation
import Testing
@testable import DuoUpdaterCore

struct HTTPAutomaticUpdateFailureSimulationTests {
    private typealias Policy = AutomaticUpdateFailurePolicy
    private typealias Ledger = RunningAppAutoUpdate.Ledger
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let key = "com.example.http-failure:/scratch/Target.app"

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost,
                      .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet])
    func explicitTransportFailuresMayRecoverOnlyDuringAcquisition(code: URLError.Code) throws {
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0.5))
        attempt.record(URLError(code))
        let capture = try #require(attempt.capture)
        #expect((capture.error as? URLError)?.code == code)
        #expect(capture.evidence.stage == .downloading(fraction: 0.5))
        #expect(try #require(attempt.failure(or: "missing")).disposition == .retryAcquisition)
        // A host that actually quit the app has stronger evidence than an
        // incomplete progress stream: it must never replay as acquisition-only.
        #expect(try #require(attempt.failure(or: "missing", appWasQuit: true)).disposition == .pauseVersion)
    }

    @Test(arguments: [URLError.Code.secureConnectionFailed, .serverCertificateUntrusted,
                      .userAuthenticationRequired, .badServerResponse, .unknown])
    func TLSAuthenticationAndUnknownURLFailuresPauseTheOffer(code: URLError.Code) throws {
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        attempt.record(URLError(code))
        #expect(try #require(attempt.failure(or: "missing")).disposition == .pauseVersion)
    }

    @Test func localIntegrityContentAndUnknownErrorsNeverAcquireRetryPermissionFromTheirText() throws {
        struct LooksLikeHTTP503: LocalizedError {
            var errorDescription: String? { "The server returned HTTP 503 instead of the file." }
        }
        let errors: [any Error] = [
            SignatureVerifier.VerifyError.edSignatureInvalid,
            VendorInstaller.InstallError.checksumMismatch,
            VendorInstaller.InstallError.htmlInsteadOfArchive,
            CocoaError(.fileWriteNoPermission),
            DiskSpaceGuard.InsufficientSpace(needed: 100, free: 0),
            LooksLikeHTTP503(),
        ]
        for error in errors {
            let attempt = Policy.Attempt()
            attempt.observe(.downloading(fraction: 0.5))
            attempt.record(error)
            let failure = try #require(attempt.failure(or: "missing"))
            #expect(failure.disposition == .pauseVersion, "\(type(of: error))")
            #expect(failure.reason == error.localizedDescription)
        }
    }

    @Test func missingAcquisitionEvidenceFailsClosed() throws {
        for stage: InstallStage? in [nil, .queued, .checking, .backingUp] {
            let attempt = Policy.Attempt()
            if let stage { attempt.observe(stage) }
            attempt.record(Downloader.DownloadError.httpStatus(503))
            #expect(try #require(attempt.failure(or: "missing")).disposition == .pauseVersion)
        }
        let earlyOut = Policy.Attempt()
        #expect(earlyOut.failure(or: "A pre-install recheck regressed") ==
            Policy.Failure(disposition: .pauseVersion, reason: "A pre-install recheck regressed"))
    }

    @Test(arguments: [InstallStage.verifyingSignature, .extracting, .verifyingCodeSignature,
                      .installing, .runningCommand("fixture"), .done])
    func fallbackDownloadingCannotEraseEarlierApplyEvidence(stage: InstallStage) throws {
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 1))
        attempt.observe(stage)
        attempt.observe(.downloading(fraction: 0))
        attempt.record(Downloader.DownloadError.httpStatus(503))
        let capture = try #require(attempt.capture)
        #expect(capture.evidence.stage == .downloading(fraction: 0))
        #expect(capture.evidence.advancedPastAcquisition)
        #expect(try #require(attempt.failure(or: "missing")).disposition == .pauseVersion)
    }

    @Test func completedAcquisitionAloneBlocksReplayEvenBeforeAnyVerificationStage() throws {
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 1))
        attempt.finishedAcquisition()
        attempt.record(URLError(.timedOut))
        let capture = try #require(attempt.capture)
        #expect(capture.evidence.acquisitionFinished)
        #expect(!capture.evidence.advancedPastAcquisition)
        #expect(try #require(attempt.failure(or: "missing")).disposition == .pauseVersion)
    }

    /// Create the callbacks inside the attempt, then invoke them where task
    /// locals are absent. Reading the TaskLocal only on callback execution
    /// would lose both monotonic markers and incorrectly allow a daily replay.
    @Test func callbacksCarryTheirAttemptAcrossDetachedTasksAndDispatch() async throws {
        let attempt = Policy.Attempt()
        let (progress, downloaded) = Policy.$attempt.withValue(attempt) {
            (Policy.recordingProgress { _ in }, Policy.afterDownload {})
        }
        await Task.detached {
            #expect(Policy.attempt == nil)
            await downloaded()
        }.value
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                #expect(Policy.attempt == nil)
                progress(.verifyingSignature)
                progress(.downloading(fraction: 0))
                continuation.resume()
            }
        }
        await Policy.$attempt.withValue(attempt) {
            await #expect(throws: Downloader.DownloadError.self) {
                try await Policy.capturing { throw Downloader.DownloadError.httpStatus(503) }
            }
        }
        let capture = try #require(attempt.capture)
        #expect(capture.evidence.acquisitionFinished)
        #expect(capture.evidence.advancedPastAcquisition)
        #expect(try #require(attempt.failure(or: "missing")).disposition == .pauseVersion)
    }

    @Test func installJobTaskInheritsTheProductionCaptureAttempt() async throws {
        let attempt = Policy.Attempt()
        await Policy.$attempt.withValue(attempt) {
            await InstallJobs.run("ZZFixture-http-policy-\(UUID().uuidString)") {
                #expect(Policy.attempt === attempt)
                let progress = Policy.recordingProgress { _ in }
                progress(.downloading(fraction: 0))
                do {
                    try await Policy.capturing { throw Downloader.DownloadError.httpStatus(429) }
                } catch {}
            }
        }
        #expect(try #require(attempt.failure(or: "missing")).disposition == .retryAcquisition)
    }

    @Test func realTaskCancellationAndSafetyDeferralsDoNotBecomeFailures() async throws {
        let cancelled = Policy.Attempt()
        let release = InstallCommitTests.Signal()
        let task = Task {
            await release.wait()
            #expect(Task.isCancelled)
            try await Policy.$attempt.withValue(cancelled) {
                try await Policy.capturing { try Task.checkCancellation() }
            }
        }
        task.cancel()
        release.fire()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(cancelled.capture?.decision == .ignore)
        #expect(cancelled.failure(or: "must not manufacture a failure", appWasQuit: true) == nil)

        for error: any Error in [URLError(.cancelled), AutomaticInstall.Deferred("permission revoked")] {
            let attempt = Policy.Attempt()
            attempt.observe(.installing)
            attempt.record(error)
            #expect(attempt.capture?.decision == .ignore)
            #expect(attempt.failure(or: "must not manufacture a failure", appWasQuit: true) == nil)
        }
    }

    @Test func acquisitionRecoveryHasItsOwnBoundedBudgetAndPersistsAtTheLimit() throws {
        #expect(Policy.maxAcquisitionFailures == 3)
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        let failure = try acquisitionFailure()
        for attemptNumber in 1...3 {
            let at = now.addingTimeInterval(Double(attemptNumber - 1) * 86_400)
            ledger.recordFailure(key, failure: failure, now: at)
            ledger = try restored(ledger)
            let entry = try #require(ledger.entries[key])
            #expect(entry.failures == 0)
            #expect(!entry.gaveUp)
            #expect(entry.acquisitionFailures == attemptNumber)
            if attemptNumber < 3 {
                #expect(entry.retryAfter == at.addingTimeInterval(86_400))
                #expect(RunningAppAutoUpdate.decide(entry: entry, now: at.addingTimeInterval(300)) == .wait(.retryLater))
                #expect(RunningAppAutoUpdate.decide(entry: entry, now: at.addingTimeInterval(86_400)) == .quitAndUpdate)
            } else {
                #expect(entry.retryAfter == nil)
                #expect(entry.automaticFailure?.disposition == .pauseVersion)
                #expect(RunningAppAutoUpdate.decide(entry: entry, now: at.addingTimeInterval(864_000)) ==
                    .wait(.pausedFailure(failure.reason)))
            }
        }
    }

    @Test func aChangedOfferClearsOnlyNewPolicyCooldownsAndRefusedQuitsStillKeepTheirs() throws {
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        ledger.recordFailure(key, failure: try acquisitionFailure(), now: now)
        let changed = ledger.observe(key, version: "2.1", now: now.addingTimeInterval(300))
        #expect(changed.automaticFailure == nil)
        #expect(changed.acquisitionFailures == nil)
        #expect(changed.retryAfter == nil)
        #expect(RunningAppAutoUpdate.decide(entry: changed, now: now.addingTimeInterval(300)) == .quitAndUpdate)

        ledger.recordFailure(key, failure: try acquisitionFailure(), now: now.addingTimeInterval(300))
        let refusalDate = now.addingTimeInterval(86_700)
        ledger.recordQuitRefused(key, now: refusalDate)
        ledger = try restored(ledger)
        let afterRefusal = ledger.observe(key, version: "3.0", now: refusalDate.addingTimeInterval(300))
        #expect(afterRefusal.automaticFailure == nil)
        #expect(!afterRefusal.gaveUp)
        #expect(afterRefusal.retryAfter == refusalDate.addingTimeInterval(86_400))
        #expect(RunningAppAutoUpdate.decide(entry: afterRefusal, now: refusalDate.addingTimeInterval(300)) == .wait(.retryLater))
    }

    @Test func aSinglePermanentFailurePersistsWithoutClaimingThreeInstallFailures() throws {
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        let error = Downloader.DownloadError.httpStatus(403)
        attempt.record(error)
        ledger.recordFailure(key, failure: try #require(attempt.failure(or: "missing")), now: now)
        ledger = try restored(ledger)
        let entry = try #require(ledger.entries[key])
        #expect(entry.failures == 0)
        #expect(entry.acquisitionFailures == nil)
        #expect(entry.retryAfter == nil)
        #expect(RunningAppAutoUpdate.decide(entry: entry, now: now.addingTimeInterval(864_000)) ==
            .wait(.pausedFailure(error.localizedDescription)))
        #expect(RunningAppAutoUpdate.Reason.pausedFailure(error.localizedDescription).message == error.localizedDescription)
        let same = ledger.observe(key, version: "2.0", now: now.addingTimeInterval(864_000))
        #expect(same == entry)
        let next = ledger.observe(key, version: "2.1", now: now.addingTimeInterval(864_000))
        #expect(next.automaticFailure == nil)
        #expect(RunningAppAutoUpdate.decide(entry: next, now: now.addingTimeInterval(864_000)) == .quitAndUpdate)
    }

    @Test func legacyJSONAndItsCrossVersionCooldownRemainUnchanged() throws {
        let json = #"{"entries":{"legacy":{"version":"2.0","firstSeen":815801466.5,"failures":1,"gaveUp":false,"retryAfter":815887866.5}}}"#
        var ledger = try JSONDecoder().decode(Ledger.self, from: Data(json.utf8))
        let entry = try #require(ledger.entries["legacy"])
        #expect(entry.automaticFailure == nil)
        #expect(entry.acquisitionFailures == nil)
        let beforeRetry = try #require(entry.retryAfter).addingTimeInterval(-300)
        let changed = ledger.observe("legacy", version: "2.1", now: beforeRetry)
        #expect(changed.retryAfter == entry.retryAfter)
        #expect(RunningAppAutoUpdate.decide(entry: changed, now: beforeRetry) == .wait(.retryLater))
    }

    @Test func aTypedServerDeadlineCannotBeShortenedToTheLocalDayLongCooldown() throws {
        let serverDeadline = now.addingTimeInterval(172_800)
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        attempt.record(Downloader.DownloadError.httpStatusAfter(429, serverDeadline))
        let failure = try #require(attempt.failure(or: "missing"))
        #expect(failure.disposition == .retryAcquisition)
        #expect(failure.retryNotBefore == serverDeadline)
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        ledger.recordFailure(key, failure: failure, now: now)
        ledger = try restored(ledger)
        let entry = try #require(ledger.entries[key])
        #expect(entry.retryAfter == serverDeadline)
        #expect(entry.automaticFailure?.retryNotBefore == serverDeadline)
        #expect(RunningAppAutoUpdate.decide(entry: entry, now: now.addingTimeInterval(86_400)) == .wait(.retryLater))
        #expect(RunningAppAutoUpdate.decide(entry: entry, now: serverDeadline.addingTimeInterval(-1)) == .wait(.retryLater))
        #expect(RunningAppAutoUpdate.decide(entry: entry, now: serverDeadline) == .quitAndUpdate)

        let shorter = Policy.Failure(disposition: .retryAcquisition, reason: failure.reason,
                                     retryNotBefore: now.addingTimeInterval(3_600))
        var shortLedger = Ledger()
        _ = shortLedger.observe(key, version: "2.0", now: now)
        shortLedger.recordFailure(key, failure: shorter, now: now)
        #expect(shortLedger.entries[key]?.retryAfter == now.addingTimeInterval(86_400))
    }

    @Test(arguments: [403, 416])
    func aServerDeadlineDoesNotUnlockAPermanentRefusal(status: Int) throws {
        let deadline = now.addingTimeInterval(172_800)
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        attempt.record(Downloader.DownloadError.httpStatusAfter(status, deadline))
        let failure = try #require(attempt.failure(or: "missing"))
        #expect(failure.disposition == .pauseVersion)
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        ledger.recordFailure(key, failure: failure, now: now)
        let entry = try #require(ledger.entries[key])
        #expect(entry.retryAfter == nil)
        #expect(RunningAppAutoUpdate.decide(entry: entry, now: deadline.addingTimeInterval(86_400)) ==
            .wait(.pausedFailure(failure.reason)))
    }

    @Test func anAlreadyPersistedFailureDecodesWithoutAServerDeadline() throws {
        let json = #"{"disposition":"retryAcquisition","reason":"The connection timed out."}"#
        let failure = try JSONDecoder().decode(Policy.Failure.self, from: Data(json.utf8))
        #expect(failure.retryNotBefore == nil)
        var ledger = Ledger()
        _ = ledger.observe(key, version: "2.0", now: now)
        ledger.recordFailure(key, failure: failure, now: now)
        #expect(ledger.entries[key]?.retryAfter == now.addingTimeInterval(86_400))
    }

    private func acquisitionFailure() throws -> Policy.Failure {
        let attempt = Policy.Attempt()
        attempt.observe(.downloading(fraction: 0))
        attempt.record(Downloader.DownloadError.httpStatus(503))
        return try #require(attempt.failure(or: "missing"))
    }

    private func restored(_ ledger: Ledger) throws -> Ledger {
        try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
    }
}
