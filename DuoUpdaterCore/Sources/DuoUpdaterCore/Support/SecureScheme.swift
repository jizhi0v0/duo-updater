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

    /// Throw unless `url` is served over HTTPS. Everything we install is fetched
    /// from a vendor CDN or GitHub, all of which serve TLS; the only plaintext
    /// `http://` URL anywhere in the recipe set is a *version probe*, not a
    /// download, so requiring HTTPS here costs us nothing and closes a real
    /// downgrade vector.
    static func requireSecureDownload(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw SchemeError.insecureDownload(
                scheme: url.scheme ?? "?",
                host: url.host ?? url.absoluteString)
        }
    }
}
