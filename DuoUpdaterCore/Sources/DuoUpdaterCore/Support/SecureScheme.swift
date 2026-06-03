import Foundation

/// Enforces that we only ever download *code* over TLS.
///
/// macOS App Transport Security already blocks cleartext HTTP loads by default,
/// so a plain-`http://` download would fail anyway — but failing it ourselves,
/// before the request is even made, buys three things:
///   1. a single, unit-testable choke point shared by every installer
///      (Sparkle / Vendor / GitHub / pkg) — they all route through `Downloader`,
///   2. a clear, actionable error instead of ATS's generic `-1022`, and
///   3. defense in depth if a future build ever relaxes ATS.
///
/// This guards the *download* of an executable payload. Version-probe endpoints
/// are a separate, lower-stakes concern: a probe served over http can lie about
/// the latest version, but it still can't get a substituted binary past the
/// EdDSA / Team-ID / bundle-ID gates that run after the download.
enum SecureScheme {

    enum SchemeError: LocalizedError {
        case insecureDownload(scheme: String, host: String)

        var errorDescription: String? {
            switch self {
            case .insecureDownload(let scheme, let host):
                return "Refusing to download the update over an insecure connection "
                    + "(\(scheme)://\(host)). Updates must be served over HTTPS."
            }
        }
    }

    /// Throw unless `url` is safe to download executable content from. Everything
    /// we install from the recipe set is fetched from a vendor CDN or GitHub, all
    /// of which serve TLS; the only plaintext `http://` URL anywhere is a *version
    /// probe*, not a download, so requiring TLS for downloads costs us nothing and
    /// closes a real downgrade vector.
    ///
    /// Allowed: `https://` (any host), `file://` (local, no network), and `http://`
    /// to the **loopback** interface only. Loopback can't be network-MITM'd, so
    /// plaintext there carries none of the downgrade risk — this mirrors App
    /// Transport Security's own loopback exemption and keeps local test servers and
    /// on-box endpoints usable. Plaintext `http://` to any other host is refused,
    /// as is every other scheme.
    static func requireSecureDownload(_ url: URL) throws {
        switch url.scheme?.lowercased() {
        case "https", "file":
            return
        case "http" where isLoopback(url.host):
            return
        default:
            throw SchemeError.insecureDownload(
                scheme: url.scheme ?? "?",
                host: url.host ?? url.absoluteString)
        }
    }

    /// True for the loopback host names/addresses that can't be intercepted on the
    /// network.
    private static func isLoopback(_ host: String?) -> Bool {
        switch host?.lowercased() {
        case "localhost", "127.0.0.1", "::1": return true
        default: return false
        }
    }
}
