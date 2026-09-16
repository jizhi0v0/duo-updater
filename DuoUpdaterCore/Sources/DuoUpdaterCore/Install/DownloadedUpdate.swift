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

    /// Set when `archiveURL` is a binary PATCH rather than a full archive — the
    /// apply phase then reconstructs the new bundle from the installed one instead
    /// of unpacking. Carries the patch's own `edSignature`, which signs different
    /// bytes than the archive's and is the only one that can verify this file.
    /// Nil for an ordinary full download.
    public let appliedPatch: DeltaPatch?

    /// Set when `archiveURL` is a copy of an installer the app's OWN updater had
    /// already downloaded, rather than the artifact our route resolved — see
    /// `SelfUpdaterStash`.
    ///
    /// Load-bearing in `apply`, not just informational: these are a different
    /// container from the one the route publishes (OpenCode's rule selects a dmg;
    /// electron-updater only ever downloads a zip), so the route's
    /// `expectedSHA512` and `nestedArchivePath` describe bytes that are not these
    /// and must not be run against them. Same reasoning as `appliedPatch`, which
    /// carries its own signature for the same reason.
    public let localStash: LocalStagedInstaller?

    public init(
        archiveURL: URL, bytesDownloaded: Int64, workDir: URL,
        finalHost: String? = nil, appliedPatch: DeltaPatch? = nil,
        localStash: LocalStagedInstaller? = nil
    ) {
        self.archiveURL = archiveURL
        self.bytesDownloaded = bytesDownloaded
        self.workDir = workDir
        self.finalHost = finalHost
        self.appliedPatch = appliedPatch
        self.localStash = localStash
    }
}
