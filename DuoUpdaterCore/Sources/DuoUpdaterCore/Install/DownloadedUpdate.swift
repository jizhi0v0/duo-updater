import Foundation

/// What an installer's download phase hands to its apply phase: the fetched
/// archive plus the accounting. The seam exists so a caller can hold a
/// *download* permit only while fetching bytes and an *apply* permit while
/// extracting/verifying/swapping — the two resources an install consumes at
/// different times (see `InstallPermits`).
public struct DownloadedUpdate: Sendable {
    /// The fetched archive, ready for extraction.
    public let archiveURL: URL
    /// Exact bytes pulled over the network, for per-app traffic accounting.
    public let bytesDownloaded: Int64
    /// Scratch dir the archive lives in. Owned by the caller between `download`
    /// and `apply`: `download` leaves it in place on success, and the caller
    /// removes it on every path from there — an `apply` failure, or a
    /// cancellation landing between the phases. On download failure the dir is
    /// removed by `download` itself.
    public let workDir: URL
    /// The host that actually served the bytes, after redirects — the feed URL
    /// often bounces to a CDN, which is what the per-host install gate should
    /// key on. Nil for a `file://` copy or when the transfer never got a
    /// response.
    public let finalHost: String?

    public init(archiveURL: URL, bytesDownloaded: Int64, workDir: URL, finalHost: String? = nil) {
        self.archiveURL = archiveURL
        self.bytesDownloaded = bytesDownloaded
        self.workDir = workDir
        self.finalHost = finalHost
    }
}
