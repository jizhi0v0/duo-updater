import Foundation

/// One HTTP transaction, recorded with everything `URLSessionTaskMetrics`
/// reports about it.
///
/// **One event per redirect hop, not per task.** A feed that 302s to a CDN
/// really did open connections to two hosts, resolve two names and negotiate two
/// TLS sessions; collapsing that into one row would answer "which hosts does
/// this app talk to" wrongly. ``taskID`` and ``hopIndex`` put the hops back
/// together, so nothing is lost either way.
///
/// Every field here is copied straight off the platform's own measurement. None
/// of it is summarised, bucketed or rounded at write time — that is the whole
/// point of keeping events (see ``DuoEvent``). The derived rollups live in
/// ``RequestLedger`` and can be rebuilt from these.
public struct RequestEvent: Codable, Sendable, Hashable {

    // MARK: What was asked, and why

    /// What the request was *for*. The one dimension the platform cannot supply
    /// and a hostname cannot stand in for: `github.com` answers a version check,
    /// a changelog page and an installer download.
    public let purpose: RequestPurpose
    public let method: String
    public let scheme: String?
    public let host: String
    public let port: Int?
    /// Path only — **the query is deliberately dropped, and that is a privacy
    /// boundary rather than brevity.** Credentials live in query strings here:
    /// CleanShot's activation key rides in one, which is why
    /// `CredentialBearingURL` exists at all. This log is plaintext on disk under
    /// Application Support, readable by anything running as the user and copied
    /// into every unencrypted backup — the same reasoning that set
    /// `diskCapacity: 0` on `URLSession.updates`. Headers and bodies are never
    /// recorded, for the same reason.
    public let path: String

    /// Whether the request carried a query string, **without carrying it**.
    ///
    /// One bit, because dropping the query silently makes the log lie by
    /// omission: `ime.doubao.com/api/v1/app/download_url` is a complete-looking
    /// URL whose entire meaning was in the part we refuse to store, and pasting
    /// it somewhere gets you a different request. The row can now say so.
    ///
    /// Nil for every row written before this existed — which is not the same as
    /// "no query", and is why it is not a plain `Bool`.
    public let hadQuery: Bool?

    /// Which task this hop belonged to, so the hops of one logical fetch regroup.
    /// Which app this request was made *for*, as ``InstalledApp/id`` — the
    /// bundle's path.
    ///
    /// Not derivable from anything else on the row, which is the reason it is
    /// stored: `objects.githubusercontent.com/…/asset/12345` says nothing about
    /// which app it belongs to, so without this the log can answer "what did it
    /// fetch" and never "what was it doing that for". Filled by
    /// ``RequestAttribution`` at the point the request is made rather than
    /// threaded through forty call sites.
    ///
    /// Nil is normal and permanent: the Homebrew catalog and the updater's own
    /// self-update are not made on behalf of any one app, and every row written
    /// before this field existed has none.
    public let appID: String?

    public let taskID: UUID
    /// 0 for the first request, 1 for the first redirect target, and so on.
    public let hopIndex: Int
    /// Redirects the whole task followed, as the task reported it.
    public let redirectCount: Int

    // MARK: What came back

    /// HTTP status, or nil when there was no HTTP response at all — a transport
    /// failure, a cancellation, or a non-HTTP scheme.
    public let status: Int?
    /// The error the *task* ended with, when it ended badly. Not part of the
    /// metrics; taken from the task, because "which host keeps failing, and how"
    /// is one of the questions a request log exists to answer and a bare nil
    /// status cannot.
    public let errorDomain: String?
    public let errorCode: Int?

    // MARK: How it was served

    public let fetchType: FetchType
    /// True when the connection was already open. A sweep whose connections are
    /// all reused costs very differently from one paying for a handshake each
    /// time, and only this field can tell them apart after the fact.
    public let reusedConnection: Bool
    public let proxyConnection: Bool
    public let cellular: Bool
    public let expensive: Bool
    public let constrained: Bool
    public let multipath: Bool
    public let domainResolution: DomainResolution
    public let networkProtocol: String?

    public let localAddress: String?
    public let localPort: Int?
    /// The address actually connected to. Nil for a cache hit — left nil rather
    /// than zero-filled, because "no socket was opened" and "connected to port 0"
    /// are different claims and only one of them is true.
    public let remoteAddress: String?
    public let remotePort: Int?

    /// Negotiated TLS version, as the platform's raw `tls_protocol_version_t`.
    /// Kept raw with a rendered ``tlsVersionName``: the numbers are stable and a
    /// name this build has not heard of would otherwise be recorded as "unknown"
    /// forever.
    public let tlsVersion: Int?
    /// Negotiated cipher suite, raw `tls_ciphersuite_t`. Not named here on
    /// purpose — the IANA registry moves and a stale table would misreport rather
    /// than admit ignorance.
    public let tlsCipherSuite: Int?

    // MARK: What it cost

    /// On the wire, i.e. after compression, headers counted separately from body.
    ///
    /// Headers matter and are not noise: a revalidating version check is *all*
    /// header — that is what `versionFeedCachePolicy` is for — so a ledger that
    /// counted only bodies would report a full sweep of 304s as costing nothing.
    public let requestHeaderBytes: Int64
    public let requestBodyBytes: Int64
    public let requestBodyBytesBeforeEncoding: Int64
    public let responseHeaderBytes: Int64
    public let responseBodyBytes: Int64
    /// After decompression. Kept alongside the wire count rather than instead of
    /// it: the wire figure is what the connection cost, this one is what the
    /// server actually sent, and a gzipped appcast makes them differ by 5×.
    public let responseBodyBytesAfterDecoding: Int64
    public let byteSource: RequestByteSource

    // MARK: When

    /// Absolute instants, kept as the platform reported them (any of which can be
    /// missing — a cache hit has no DNS phase, a reused connection no handshake).
    /// Stored rather than pre-differenced so a later reader can ask for a phase
    /// nobody thought to compute today.
    public let fetchStart: Date?
    public let domainLookupStart: Date?
    public let domainLookupEnd: Date?
    public let connectStart: Date?
    public let secureConnectionStart: Date?
    public let secureConnectionEnd: Date?
    public let connectEnd: Date?
    public let requestStart: Date?
    public let requestEnd: Date?
    public let responseStart: Date?
    public let responseEnd: Date?

    public enum FetchType: String, Codable, Sendable {
        case unknown, networkLoad, serverPush, localCache
    }

    public enum DomainResolution: String, Codable, Sendable {
        case unknown, udp, tcp, tls, https
    }

    // MARK: Derived reads (never stored)

    /// Total bytes off the wire for this hop.
    public var bytesReceived: Int64 { responseHeaderBytes + responseBodyBytes }
    /// Total bytes onto the wire for this hop.
    public var bytesSent: Int64 { requestHeaderBytes + requestBodyBytes }
    public var fromCache: Bool { fetchType == .localCache }
    /// The server was asked and answered "unchanged" — the cheapest possible
    /// non-free request, and the one `versionFeedCachePolicy` produces by design.
    public var isNotModified: Bool { status == 304 }
    /// Nothing came back and it was not a cache hit.
    public var failed: Bool { status == nil && !fromCache }

    /// Wall time for the hop, when both ends were measured.
    public var duration: TimeInterval? {
        guard let fetchStart, let responseEnd else { return nil }
        return responseEnd.timeIntervalSince(fetchStart)
    }

    /// Time to first byte of the response.
    public var timeToFirstByte: TimeInterval? {
        guard let fetchStart, let responseStart else { return nil }
        return responseStart.timeIntervalSince(fetchStart)
    }

    /// Human-readable TLS version for the handful of values that exist, or the
    /// raw number for anything newer than this build.
    public var tlsVersionName: String? {
        switch tlsVersion {
        case nil: return nil
        case 0x0301?: return "TLSv1.0"
        case 0x0302?: return "TLSv1.1"
        case 0x0303?: return "TLSv1.2"
        case 0x0304?: return "TLSv1.3"
        case let raw?: return String(format: "0x%04x", raw)
        }
    }

    /// The app this was for, as a name to put in a column.
    ///
    /// Derived here rather than in the view so the window and `duo` agree on
    /// what to call a bundle, and so the derivation is executed by something:
    /// `App/Sources` has no test target.
    public var appName: String? {
        guard let appID, !appID.isEmpty else { return nil }
        return URL(fileURLWithPath: appID).deletingPathExtension().lastPathComponent
    }

    public var url: String {
        var text = "\(scheme ?? "https")://\(host)"
        if let port, port != (scheme == "http" ? 80 : 443) { text += ":\(port)" }
        return text + path
    }


    // swiftlint:disable:next function_body_length
    public init(
        purpose: RequestPurpose, method: String, scheme: String?, host: String,
        port: Int?, path: String, hadQuery: Bool? = nil, appID: String? = nil,
        taskID: UUID, hopIndex: Int, redirectCount: Int,
        status: Int?, errorDomain: String? = nil, errorCode: Int? = nil,
        fetchType: FetchType, reusedConnection: Bool = false,
        proxyConnection: Bool = false, cellular: Bool = false,
        expensive: Bool = false, constrained: Bool = false, multipath: Bool = false,
        domainResolution: DomainResolution = .unknown, networkProtocol: String? = nil,
        localAddress: String? = nil, localPort: Int? = nil,
        remoteAddress: String? = nil, remotePort: Int? = nil,
        tlsVersion: Int? = nil, tlsCipherSuite: Int? = nil,
        requestHeaderBytes: Int64 = 0, requestBodyBytes: Int64 = 0,
        requestBodyBytesBeforeEncoding: Int64 = 0,
        responseHeaderBytes: Int64 = 0, responseBodyBytes: Int64 = 0,
        responseBodyBytesAfterDecoding: Int64 = 0,
        byteSource: RequestByteSource = .measured,
        fetchStart: Date? = nil, domainLookupStart: Date? = nil,
        domainLookupEnd: Date? = nil, connectStart: Date? = nil,
        secureConnectionStart: Date? = nil, secureConnectionEnd: Date? = nil,
        connectEnd: Date? = nil, requestStart: Date? = nil, requestEnd: Date? = nil,
        responseStart: Date? = nil, responseEnd: Date? = nil
    ) {
        self.purpose = purpose
        self.method = method
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.hadQuery = hadQuery
        self.appID = appID
        self.taskID = taskID
        self.hopIndex = hopIndex
        self.redirectCount = redirectCount
        self.status = status
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.fetchType = fetchType
        self.reusedConnection = reusedConnection
        self.proxyConnection = proxyConnection
        self.cellular = cellular
        self.expensive = expensive
        self.constrained = constrained
        self.multipath = multipath
        self.domainResolution = domainResolution
        self.networkProtocol = networkProtocol
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.tlsVersion = tlsVersion
        self.tlsCipherSuite = tlsCipherSuite
        self.requestHeaderBytes = requestHeaderBytes
        self.requestBodyBytes = requestBodyBytes
        self.requestBodyBytesBeforeEncoding = requestBodyBytesBeforeEncoding
        self.responseHeaderBytes = responseHeaderBytes
        self.responseBodyBytes = responseBodyBytes
        self.responseBodyBytesAfterDecoding = responseBodyBytesAfterDecoding
        self.byteSource = byteSource
        self.fetchStart = fetchStart
        self.domainLookupStart = domainLookupStart
        self.domainLookupEnd = domainLookupEnd
        self.connectStart = connectStart
        self.secureConnectionStart = secureConnectionStart
        self.secureConnectionEnd = secureConnectionEnd
        self.connectEnd = connectEnd
        self.requestStart = requestStart
        self.requestEnd = requestEnd
        self.responseStart = responseStart
        self.responseEnd = responseEnd
    }
}
