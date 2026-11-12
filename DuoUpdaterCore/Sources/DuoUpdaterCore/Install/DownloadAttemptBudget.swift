import Foundation

/// One artifact acquisition shares this across transport resumes and HTML-body
/// recovery. Each URLSession data task consumes one slot; redirects within that
/// task do not consume additional slots. A standalone Downloader gets its own.
final class DownloadAttemptBudget: @unchecked Sendable {
    @TaskLocal static var current: DownloadAttemptBudget?

    private let lock = NSLock()
    private var remaining = DownloadRetryPolicy.maxAttempts
    private var lastFailure: Error?

    private struct Exhausted: LocalizedError {
        var errorDescription: String? {
            "The update download used all \(DownloadRetryPolicy.maxAttempts) network attempts."
        }
    }

    var hasRemaining: Bool { lock.withLock { remaining > 0 } }

    func beginAttempt() throws {
        try lock.withLock {
            guard remaining > 0 else { throw lastFailure ?? Exhausted() }
            remaining -= 1
        }
    }

    func recordFailure(_ error: Error) {
        lock.withLock { lastFailure = error }
    }
}
