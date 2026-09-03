import Foundation

public extension URLSession {

    /// The HTTP statuses a *version feed* request retries once, and nothing else.
    ///
    /// All three mean "an intermediary could not reach the origin right now" —
    /// they carry no claim about the request itself, so the same bytes sent a
    /// moment later routinely succeed. Headlamp's check died on exactly this:
    /// `api.github.com` answered 504 with no `X-RateLimit-Remaining` header at
    /// all, i.e. the request never reached GitHub's application layer.
    ///
    /// What is deliberately *not* here matters more than what is:
    ///
    /// - **500** — an origin that did reach the application and threw. Repeating
    ///   it usually reproduces it, and a vendor whose feed 500s consistently is a
    ///   broken recipe we want to see reported, not smoothed over.
    /// - **403 / 429** — GitHub's unauthenticated 60/hour limit. Retrying a rate
    ///   limit spends the budget it is complaining about and brings the reset
    ///   nearer; `UpdateStatus.isRateLimitError` already drives a proper UI nudge.
    /// - **4xx generally** — a definitive answer about *this* request.
    static let retryableGatewayStatuses: Set<Int> = [502, 503, 504]

    /// How long to wait before the single retry.
    ///
    /// Long enough that we are not re-asking the same wedged edge node in the
    /// same instant, short enough to stay inside one update-check round rather
    /// than stretching a 130-app fan-out. It is a fixed pause, not a growing
    /// backoff, because there is only ever one retry to schedule.
    static let gatewayRetryDelay: Duration = .milliseconds(800)

    /// GET a version feed, retrying **exactly once** when the answer is a
    /// gateway 5xx (see ``retryableGatewayStatuses``).
    ///
    /// The retry is invisible to the caller: this returns whatever the second
    /// attempt produced, so every existing status guard keeps its own meaning —
    /// a source that throws on non-2xx still throws, one that returns nil still
    /// returns nil. On any other status (including a 5xx not in the set) the
    /// first response is handed back untouched and no second request is made.
    ///
    /// Only for **idempotent GETs on the update-check path**. A POST that
    /// mints a token or otherwise changes server state must not go through here.
    ///
    /// A transport-level failure (`URLError`) is not retried: `Downloader` owns
    /// that policy for the bytes that matter, and a source that cannot connect
    /// at all is already reported as a retryable row.
    ///
    /// `retryableBody` earns the same one retry for a vendor that reports its own
    /// outage **inside a 200**: an error envelope where the answer should be. That
    /// is a gateway 5xx wearing a success costume — it says nothing about the
    /// request, and the same bytes a moment later work — so it belongs on this
    /// path rather than in a second retry loop somewhere above. Nil for every
    /// caller but a vendor probe whose recipe declares the envelope's shape; the
    /// predicate is never consulted otherwise.
    ///
    /// **It is consulted on 2xx only**, and that gate is the important half. A
    /// rejection carries an empty body far more often than an answer does, so a
    /// predicate written against "no payload" would match a 429 or a 500 too —
    /// and retrying those is precisely what the rules above refuse to do, for
    /// reasons (spending the rate-limit budget you are being told about,
    /// reproducing an origin's own exception) that a body shape does not change.
    /// A success status is what makes this a *disguised* outage rather than a
    /// stated one.
    func versionFeedData(
        for request: URLRequest,
        label: String,
        retryDelay: Duration = URLSession.gatewayRetryDelay,
        retryableBody: (@Sendable (Data) -> Bool)? = nil
    ) async throws -> (Data, URLResponse) {
        let first = try await data(for: request)
        let http = first.1 as? HTTPURLResponse
        // What we would be retrying, in the words the log line wants. Nil means the
        // answer is settled and this returns untouched — the path every caller that
        // passes no predicate keeps taking.
        let reason: String
        if let http, Self.retryableGatewayStatuses.contains(http.statusCode) {
            reason = "HTTP \(http.statusCode)"
        } else if let http, (200..<300).contains(http.statusCode),
                  retryableBody?(first.0) == true {
            reason = "\(first.0.count)-byte error body"
        } else {
            return first
        }
        // Safe by construction rather than by every caller remembering: a body-carrying
        // method is not ours to send twice. `VendorProbeSource` builds GET and POST
        // probes through one code path (`recipe.requestBody` decides), so the guard has
        // to live here — a call site that "knows" it is a GET is one recipe away from
        // being wrong. nil means GET.
        let method = (request.httpMethod ?? "GET").uppercased()
        guard method == "GET" || method == "HEAD" else {
            Log.source.info(
                "\(label, privacy: .public): \(reason, privacy: .public) on \(method, privacy: .public) — not retried")
            return first
        }

        // `.info` rather than the `.debug` this file's own convention gives HTTP
        // statuses: this is not a status, it is us deciding to send a second
        // request. When the retry succeeds nothing else logs at all — the source's
        // `.error` never fires — so at `.debug` a gateway hiccup would leave no
        // trace anywhere.
        Log.source.info(
            "\(label, privacy: .public): \(reason, privacy: .public) — retrying once")
        GatewayRetry.tally?.record()
        // Cancellation must not change the *shape* of the failure a caller sees.
        // `Task.sleep` throws `CancellationError`, which is not a `URLError`, and
        // `VendorProbeSource.transportFailure` would render it as "URLError 1" — a
        // code that does not exist. Cancelling a `data(for:)` has always produced
        // `URLError(.cancelled)`; keep that, so every existing catch stays honest.
        do { try await Task.sleep(for: retryDelay) }
        catch { throw URLError(.cancelled) }
        let second = try await data(for: request)
        let status = (second.1 as? HTTPURLResponse)?.statusCode
        Log.source.info(
            "\(label, privacy: .public): gateway retry → \(status.map(String.init) ?? "non-HTTP", privacy: .public)")
        return second
    }
}

/// Makes the retry in ``URLSession/versionFeedData(for:label:retryDelay:)``
/// countable by whoever asked for the fetch.
///
/// The retry is deliberately invisible to callers — that is what keeps every
/// existing status guard meaning what it meant. But `duo verify` exists to notice
/// an endpoint degrading, and an endpoint that 502s and then succeeds is exactly
/// the early, cheap-to-catch kind of degradation: without a count it reports `ok`
/// with no trace that anything happened, while quietly making two requests where
/// the report claims one.
///
/// A task-local rather than a return value because the retry happens several
/// layers below anyone who cares — threading a count up through every source's
/// signature would touch a dozen call sites to serve one tool. Task-locals also
/// scope themselves to a task tree, so a concurrent sweep's recipes cannot
/// contaminate each other's counts.
public enum GatewayRetry {

    /// One sweep unit's tally. A class so the value survives being read back after
    /// the `withValue` scope ends; locked because a probe may fan out internally.
    public final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        public init() {}

        /// How many *extra* requests the gateway retry cost. Zero is the norm.
        public var count: Int {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        func record() {
            lock.lock(); value += 1; lock.unlock()
        }
    }

    /// Set by a caller that wants the count; nil everywhere else, which is why the
    /// app pays nothing for this.
    @TaskLocal public static var tally: Tally?
}
