import Foundation

/// Recovery for an unattended attempt, separate from a download's in-request
/// retries. Only a proven acquisition failure may be replayed automatically.
/// Unknown errors and failures past the final acquisition wait for a different offer
/// or an explicit manual attempt; their localized text is never classification.
public enum AutomaticUpdateFailurePolicy {
    public static let maxAcquisitionFailures = 3

    public enum Disposition: String, Codable, Equatable, Sendable {
        case retryAcquisition
        case pauseVersion
    }

    /// The small persisted part of a failure. The attempt retains its typed
    /// error and phase evidence until the host has settled the result.
    public struct Failure: Codable, Equatable, Sendable {
        public let disposition: Disposition
        public let reason: String
        /// A typed server Retry-After deadline, when the response supplied one.
        /// Optional so failures persisted before this field still decode.
        public let retryNotBefore: Date?

        public init(disposition: Disposition, reason: String, retryNotBefore: Date? = nil) {
            self.disposition = disposition
            self.reason = reason
            self.retryNotBefore = retryNotBefore
        }

        public var pausingVersion: Failure {
            Failure(disposition: .pauseVersion, reason: reason, retryNotBefore: retryNotBefore)
        }
    }

    public enum PreflightFailure: LocalizedError, Sendable {
        case answerRegressed(String)

        public var errorDescription: String? {
            switch self { case .answerRegressed(let reason): return reason }
        }
    }

    public struct Evidence: Equatable, Sendable {
        public let stage: InstallStage?
        public let acquisitionFinished: Bool
        /// Historical evidence is monotonic. Only an explicit coordinator
        /// fallback can authorize another acquisition before any quit/commit.
        public let advancedPastAcquisition: Bool
        public let allowedFallbackAcquisition: Bool
        public let sideEffectsStarted: Bool
    }

    public enum Decision: Equatable, Sendable {
        /// Cancellation and an expected safety deferral keep their own policy.
        case ignore
        case failure(Failure)
    }

    public struct Capture: Sendable {
        public let error: any Error
        public let evidence: Evidence
        public let decision: Decision
    }

    /// One automatic attempt's evidence, inherited through InstallJobs' task
    /// and recorded synchronously before any UI progress hop.
    public final class Attempt: @unchecked Sendable {
        private let lock = NSLock()
        private var stage: InstallStage?
        private var acquisitionFinished = false
        private var advancedPastAcquisition = false
        private var allowedFallbackAcquisition = false
        private var sideEffectsStarted = false
        private var captured: Capture?

        public init() {}

        public func observe(_ stage: InstallStage) {
            lock.withLock {
                self.stage = stage
                switch stage {
                case .queued, .checking, .backingUp, .downloading:
                    break
                case .verifyingSignature, .extracting, .verifyingCodeSignature,
                     .installing, .runningCommand, .done:
                    advancedPastAcquisition = true
                    allowedFallbackAcquisition = false
                }
            }
        }

        public func finishedAcquisition() {
            lock.withLock {
                acquisitionFinished = true
                allowedFallbackAcquisition = false
            }
        }

        /// Only the coordinator may authorize a known stash/delta fallback.
        /// Historical evidence is retained; this exemption lasts only through
        /// the fallback acquisition and can never erase a quit or commit.
        func beginAllowedFallbackAcquisition() {
            lock.withLock {
                stage = nil
                allowedFallbackAcquisition = !sideEffectsStarted
            }
        }

        func beginSideEffects() {
            lock.withLock { sideEffectsStarted = true }
        }

        public var evidence: Evidence {
            lock.withLock { snapshot() }
        }

        public var capture: Capture? {
            lock.withLock { captured }
        }

        public func record(_ error: any Error) {
            lock.withLock {
                let evidence = snapshot()
                captured = Capture(error: error, evidence: evidence,
                    decision: AutomaticUpdateFailurePolicy.decide(error, evidence: evidence))
            }
        }

        /// A host early-out can carry an error note without throwing through
        /// `capturing`. Without typed/phase evidence it pauses, never retries.
        /// A real quit also rules out acquisition-only recovery, independently
        /// of the progress reporting. Explicit cancellation stays a cancellation.
        public func failure(or reason: String, appWasQuit: Bool = false) -> Failure? {
            lock.withLock {
                switch captured?.decision {
                case .ignore:
                    return nil
                case .failure(let failure):
                    return appWasQuit ? failure.pausingVersion : failure
                case nil:
                    return Failure(disposition: .pauseVersion, reason: reason)
                }
            }
        }

        private func snapshot() -> Evidence {
            Evidence(stage: stage, acquisitionFinished: acquisitionFinished,
                     advancedPastAcquisition: advancedPastAcquisition,
                     allowedFallbackAcquisition: allowedFallbackAcquisition,
                     sideEffectsStarted: sideEffectsStarted)
        }
    }

    @TaskLocal public static var attempt: Attempt?

    /// The production coordinator call goes inside this scope, so the error
    /// remains typed when its acquisition/apply evidence is classified.
    public static func capturing<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        do { return try await body() }
        catch {
            attempt?.record(error)
            throw error
        }
    }

    public static func recordingProgress(
        _ progress: @escaping @Sendable (InstallStage) -> Void
    ) -> @Sendable (InstallStage) -> Void {
        let attempt = attempt
        return { stage in
            attempt?.observe(stage)
            progress(stage)
        }
    }

    /// InstallCoordinator calls this after a completed download and before it
    /// waits for an apply permit. It never resets during a fallback download.
    public static func afterDownload(
        _ release: @escaping @Sendable () async -> Void
    ) -> @Sendable () async -> Void {
        let attempt = attempt
        return {
            attempt?.finishedAcquisition()
            await release()
        }
    }

    private static func decide(_ error: any Error, evidence: Evidence) -> Decision {
        if error is CancellationError || error is AutomaticInstall.Deferred
            || (error as? URLError)?.code == .cancelled {
            return .ignore
        }
        let reason = error.localizedDescription
        let pause = Decision.failure(Failure(disposition: .pauseVersion, reason: reason))
        guard !evidence.sideEffectsStarted else { return pause }
        if case .answerRegressed = error as? PreflightFailure,
           !evidence.acquisitionFinished, !evidence.advancedPastAcquisition {
            return .failure(Failure(disposition: .retryAcquisition, reason: reason))
        }
        guard let stage = evidence.stage, case .downloading = stage,
              evidence.allowedFallbackAcquisition
                || (!evidence.acquisitionFinished && !evidence.advancedPastAcquisition) else { return pause }
        if case .lengthMismatch(let received, let expected) = error as? Downloader.DownloadError,
           received < expected {
            return .failure(Failure(disposition: .retryAcquisition, reason: reason))
        }
        let response: (status: Int, retryNotBefore: Date?)?
        switch error as? Downloader.DownloadError {
        case .httpStatus(let status): response = (status, nil)
        case .httpStatusAfter(let status, let deadline): response = (status, deadline)
        default: response = nil
        }
        if let response {
            switch response.status {
            case 408, 429, 500, 502, 503, 504:
                return .failure(Failure(disposition: .retryAcquisition, reason: reason,
                                        retryNotBefore: response.retryNotBefore))
            default:
                return pause
            }
        }
        guard let error = error as? URLError else { return pause }
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return .failure(Failure(disposition: .retryAcquisition, reason: reason))
        default:
            // TLS, certificates, authentication, local files and an unknown
            // URL failure do not prove a temporary connectivity problem.
            return pause
        }
    }
}
