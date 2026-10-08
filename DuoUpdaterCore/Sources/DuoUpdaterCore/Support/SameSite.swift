import Foundation

/// "The same site", strictly: the same host, or one host a subdomain of the
/// other, ignoring a leading `www.` — so `www.gnu.org` and `ftp.gnu.org` are
/// one site with `gnu.org`, and `cdn.jsdelivr.net` is not `example.org`'s.
///
/// Siblings are refused: `proj.readthedocs.io` and `other.readthedocs.io` are
/// different sites run by different people, and so, as this rule cannot tell
/// them apart without a public-suffix list, are `docs.microsoft.com` and
/// `learn.microsoft.com`. The rule only errs toward refusing. An IP address
/// matches only itself.
public enum SameSite {
    static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    static func isIPAddress(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
    }

    public static func matches(_ a: URL, _ b: URL) -> Bool {
        guard let ha = normalizedHost(a), let hb = normalizedHost(b) else { return false }
        if ha == hb { return true }
        if isIPAddress(ha) || isIPAddress(hb) { return false }
        // A bare single-label host (`localhost`) is never anyone's parent.
        guard ha.contains("."), hb.contains(".") else { return false }
        return ha.hasSuffix("." + hb) || hb.hasSuffix("." + ha)
    }

    /// Marks `request` so the update session will not follow a redirect off its
    /// site (`CrossHostCredentialStripper`). A `URLProtocol` property: it lives on
    /// the request object in this process and is never sent.
    public static func confine(_ request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest
        else { return request }
        URLProtocol.setProperty(true, forKey: propertyKey, in: mutable)
        return mutable as URLRequest
    }

    static func isConfined(_ request: URLRequest?) -> Bool {
        guard let request else { return false }
        return URLProtocol.property(forKey: propertyKey, in: request) as? Bool == true
    }

    private static let propertyKey = "com.duoupdater.sameSiteOnly"

    /// Whether a redirect of `original` to `target` may be followed.
    static func allowsRedirect(of original: URLRequest?, to target: URL?) -> Bool {
        guard isConfined(original) else { return true }
        guard let from = original?.url, let target else { return false }
        return matches(from, target)
    }
}
