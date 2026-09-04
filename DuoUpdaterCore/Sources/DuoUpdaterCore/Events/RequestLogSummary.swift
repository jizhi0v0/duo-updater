import Foundation

/// What the request log adds up to **for the question currently being asked**.
///
/// Recomputed against the live filter rather than kept as a lifetime figure: the
/// strip above the log is the answer to the query, so a fixed total sitting on
/// top of a filtered list would be two unrelated numbers with the subtraction
/// left to the reader.
///
/// In Core, not in the view, for the usual reason — `App/project.yml` has no test
/// target, so a rule written into a `body` is a rule nothing executes.
public struct RequestLogSummary: Sendable, Equatable {

    public struct PurposeSlice: Sendable, Equatable, Identifiable {
        public let purpose: RequestPurpose
        public let requests: Int
        public let bytesReceived: Int64
        public var id: String { purpose.rawValue }
    }

    public struct HostSlice: Sendable, Equatable, Identifiable {
        public let host: String
        public let requests: Int
        public let notModified: Int
        public let bytesReceived: Int64
        public var id: String { host }
    }

    public let bytesReceived: Int64
    public let bytesSent: Int64
    public let requests: Int
    public let notModified: Int
    public let cached: Int
    /// No answer, or an answer of 400 and up. Wider than a transport failure on
    /// purpose: see ``RequestQuery/StatusTerm/problem``.
    public let problems: Int
    public let oldest: Date?
    public let newest: Date?
    public let byPurpose: [PurposeSlice]
    public let hosts: [HostSlice]

    public init(
        bytesReceived: Int64 = 0, bytesSent: Int64 = 0, requests: Int = 0,
        notModified: Int = 0, cached: Int = 0, problems: Int = 0,
        oldest: Date? = nil, newest: Date? = nil,
        byPurpose: [PurposeSlice] = [], hosts: [HostSlice] = []
    ) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.requests = requests
        self.notModified = notModified
        self.cached = cached
        self.problems = problems
        self.oldest = oldest
        self.newest = newest
        self.byPurpose = byPurpose
        self.hosts = hosts
    }

    public static let empty = RequestLogSummary()

    public var hostCount: Int { hosts.count }
    public var isEmpty: Bool { requests == 0 }

    /// A slice's share of the bar. Zero when nothing was received — a sweep that
    /// was entirely 304s is real traffic with no bytes, and must not divide by
    /// zero on its way to being drawn.
    public func share(_ slice: PurposeSlice) -> Double {
        bytesReceived > 0 ? Double(slice.bytesReceived) / Double(bytesReceived) : 0
    }
}
