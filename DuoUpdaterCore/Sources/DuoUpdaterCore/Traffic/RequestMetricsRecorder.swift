import Foundation

/// Turns one task's `URLSessionTaskMetrics` into ``RequestEvent``s and files them
/// with an ``EventStore``.
///
/// **Why a per-task delegate and not the session delegate.** The purpose of a
/// request is known only at the call site, and there is no way to carry it down
/// to a session-wide delegate:
///
/// - A `@TaskLocal` (the trick ``GatewayRetry/tally`` uses) does **not** work
///   here. The metrics callback runs on the session's `delegateQueue`, outside
///   the calling task's tree — measured: a probe that set a task-local around
///   `data(for:delegate:)` read the default value back inside the callback.
/// - Stamping the purpose into a header would put it on the wire, where it is
///   both none of the server's business and a fingerprint.
///
/// `data(for:delegate:)` takes a delegate per task, which can simply hold the
/// purpose as a stored property. Two things about that were verified rather than
/// assumed, because both are load-bearing:
///
/// - **Metrics really do arrive for a completion-handler task.**
///   `URLSession.updates` fetches everything through `data(for:)`, and
///   `NSURLSession.h` warns that "the delegate methods for response and data
///   delivery are not called" for such tasks — which is why `willCacheResponse`
///   is dead on that session. That sentence is scoped to
///   `NSURLSessionDataDelegate` (`NSURLSession.h:1796`);
///   `didFinishCollectingMetrics` is declared on `NSURLSessionTaskDelegate`
///   (`:1779`) and is not covered by it. A loopback probe confirms it fires.
/// - **The session delegate keeps handling what this one does not implement.**
///   `URLSession.updates` installs `CrossHostCredentialStripper` to drop
///   `Authorization` on a cross-host redirect, and that is a security boundary,
///   not a nicety. A per-task delegate that implements only the metrics method
///   does not displace it — probed with a 302 across hosts: the session
///   delegate's `willPerformHTTPRedirection` still ran.
public final class RequestMetricsRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let purpose: RequestPurpose
    private let store: EventStore

    public init(_ purpose: RequestPurpose, store: EventStore = .shared) {
        self.purpose = purpose
        self.store = store
        super.init()
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let events = Self.events(from: metrics, task: task, purpose: purpose)
        guard !events.isEmpty else { return }
        // Synchronous hand-off, not `Task { await store.append(…) }`. This
        // callback is delivered before the fetch's continuation resumes, so
        // staging here means the events are recorded and `hasRecorded` is set by
        // the time the caller gets its bytes back — which is what lets `duo`
        // check that flag and exit without losing the last request of a run.
        store.stage(events.map {
            DuoEvent(date: $0.responseEnd ?? $0.fetchStart ?? Date(), payload: .request($0))
        })
    }

    /// One event per transaction — i.e. per redirect hop, since `URLSession`
    /// reports a transaction for each. A feed that 302s to a CDN contacted two
    /// hosts and both belong in a record of which hosts we talk to;
    /// ``RequestEvent/taskID`` and ``RequestEvent/hopIndex`` put them back
    /// together.
    ///
    /// Static and pure so a test can feed it metrics without a network.
    public static func events(
        from metrics: URLSessionTaskMetrics, task: URLSessionTask?,
        purpose: RequestPurpose
    ) -> [RequestEvent] {
        // One id for the whole task, so the hops of one logical fetch can be
        // regrouped after the fact — the thing per-hop rows would otherwise lose.
        let taskID = UUID()
        // The metrics carry no error; the task does. "Which host keeps failing,
        // and how" is a question a bare nil status cannot answer, and it is one of
        // the reasons to keep events at all.
        let error = task?.error as NSError?
        let lastHop = metrics.transactionMetrics.count - 1
        return metrics.transactionMetrics.enumerated().compactMap { index, transaction -> RequestEvent? in
            guard let url = transaction.request.url, let host = url.host else { return nil }
            let http = transaction.response as? HTTPURLResponse
            // The error belongs to the task, so it is attributed to the hop that
            // actually ended it rather than smeared over all of them, which would
            // make one failure look like three.
            let carriesError = index == lastHop
            return RequestEvent(
                purpose: purpose,
                method: transaction.request.httpMethod ?? "GET",
                scheme: url.scheme,
                host: host,
                port: url.port,
                // Path only — the query is dropped. See `RequestEvent.path`.
                path: url.path,
                taskID: taskID,
                hopIndex: index,
                redirectCount: metrics.redirectCount,
                status: http?.statusCode,
                errorDomain: carriesError ? error?.domain : nil,
                errorCode: carriesError ? error?.code : nil,
                fetchType: RequestEvent.FetchType(transaction.resourceFetchType),
                reusedConnection: transaction.isReusedConnection,
                proxyConnection: transaction.isProxyConnection,
                cellular: transaction.isCellular,
                expensive: transaction.isExpensive,
                constrained: transaction.isConstrained,
                multipath: transaction.isMultipath,
                domainResolution: RequestEvent.DomainResolution(
                    transaction.domainResolutionProtocol),
                networkProtocol: transaction.networkProtocolName,
                localAddress: transaction.localAddress,
                localPort: transaction.localPort,
                remoteAddress: transaction.remoteAddress,
                remotePort: transaction.remotePort,
                tlsVersion: transaction.negotiatedTLSProtocolVersion.map { Int($0.rawValue) },
                tlsCipherSuite: transaction.negotiatedTLSCipherSuite.map { Int($0.rawValue) },
                // Headers counted separately from bodies, and both kept: a
                // revalidating version check is *all* header, so a record that
                // dropped them would report a full sweep of 304s as free.
                requestHeaderBytes: transaction.countOfRequestHeaderBytesSent,
                requestBodyBytes: transaction.countOfRequestBodyBytesSent,
                requestBodyBytesBeforeEncoding: transaction.countOfRequestBodyBytesBeforeEncoding,
                responseHeaderBytes: transaction.countOfResponseHeaderBytesReceived,
                responseBodyBytes: transaction.countOfResponseBodyBytesReceived,
                responseBodyBytesAfterDecoding: transaction.countOfResponseBodyBytesAfterDecoding,
                byteSource: .measured,
                fetchStart: transaction.fetchStartDate,
                domainLookupStart: transaction.domainLookupStartDate,
                domainLookupEnd: transaction.domainLookupEndDate,
                connectStart: transaction.connectStartDate,
                secureConnectionStart: transaction.secureConnectionStartDate,
                secureConnectionEnd: transaction.secureConnectionEndDate,
                connectEnd: transaction.connectEndDate,
                requestStart: transaction.requestStartDate,
                requestEnd: transaction.requestEndDate,
                responseStart: transaction.responseStartDate,
                responseEnd: transaction.responseEndDate)
        }
    }
}

extension RequestEvent.FetchType {
    init(_ platform: URLSessionTaskMetrics.ResourceFetchType) {
        switch platform {
        case .networkLoad: self = .networkLoad
        case .serverPush: self = .serverPush
        case .localCache: self = .localCache
        default: self = .unknown
        }
    }
}

extension RequestEvent.DomainResolution {
    init(_ platform: URLSessionTaskMetrics.DomainResolutionProtocol) {
        switch platform {
        case .udp: self = .udp
        case .tcp: self = .tcp
        case .tls: self = .tls
        case .https: self = .https
        default: self = .unknown
        }
    }
}

public extension URLSession {

    /// `data(for:)` with the transfer recorded in the event store.
    ///
    /// A thin wrapper rather than something clever, so the recording is visible
    /// at the call site: a reader can tell which fetches are accounted for by
    /// looking, and a new one that forgets shows up as a plain `data(for:)`.
    func countedData(
        for request: URLRequest, purpose: RequestPurpose, store: EventStore = .shared
    ) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: RequestMetricsRecorder(purpose, store: store))
    }
}
