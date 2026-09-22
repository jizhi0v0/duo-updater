import Foundation

/// Fetches an Xcode `.xip` from Apple's developer site on the host's behalf.
///
/// Xcode's prereleases sit behind an Apple ID session, and that session lives in
/// an embedded web view the menu-bar app owns (WebKit, with the user's own
/// sign-in and 2FA) — so the bytes cannot come from `Downloader`'s URLSession,
/// which has no session to send. The core library routes `.xcode` installs
/// through this seam instead, and a host that cannot sign in (the `duo` CLI)
/// passes none, which makes the route refuse rather than half-work.
///
/// The authorized URL is `developer.apple.com/services-account/download?path=…`,
/// not the `download.developer.apple.com` CDN URL the release index publishes:
/// the CDN refuses a request that did not come through that endpoint first
/// (measured 2026-09-22: anonymous CDN → 302 to `/unauthorized/`; the endpoint,
/// with a live session, redirects to the CDN and the file is served).
public protocol XcodeArchiveDownloading: Sendable {
    /// Download the archive behind `authorizedURL` into `directory`.
    ///
    /// - Parameters:
    ///   - authorizedURL: the `services-account/download?path=…` URL.
    ///   - directory: an existing scratch directory owned by the caller; the
    ///     file is written inside it.
    ///   - progress: fraction completed, 0…1. May be called from any thread.
    /// - Throws: `CancellationError` when the task is cancelled (including the
    ///   user dismissing a sign-in prompt), or the host's own error otherwise.
    func downloadXcodeArchive(
        from authorizedURL: URL,
        into directory: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> XcodeArchiveDownload
}

/// What an `XcodeArchiveDownloading` host hands back.
public struct XcodeArchiveDownload: Sendable, Equatable {
    /// The downloaded `.xip`, inside the directory the caller passed.
    public let fileURL: URL
    /// Bytes actually transferred, for the per-app traffic ledger.
    public let bytesDownloaded: Int64
    /// The host that served the bytes after redirects (the CDN), or nil if unknown.
    public let finalHost: String?

    public init(fileURL: URL, bytesDownloaded: Int64, finalHost: String?) {
        self.fileURL = fileURL
        self.bytesDownloaded = bytesDownloaded
        self.finalHost = finalHost
    }
}
