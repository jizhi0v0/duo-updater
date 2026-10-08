import Foundation

/// "The same site" as a person reads a URL: the same registrable domain, so
/// `www.gnu.org` and `ftp.gnu.org` are one site and `cdn.jsdelivr.net` is not
/// `example.org`'s.
///
/// Approximate on purpose: the registrable domain is the last two labels, or
/// three under a two-letter country code whose second level is short
/// (`example.co.uk`, `example.com.cn`). No public-suffix list ships with the
/// app, and the cost of the approximation only runs one way: a host it
/// misjudges is treated as another site and refused.
public enum SameSite {
    static func registrableDomain(of host: String) -> String? {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2, !labels.contains(where: \.isEmpty) else { return nil }
        let last = labels[labels.count - 1], second = labels[labels.count - 2]
        let keep = (last.count == 2 && second.count <= 3 && labels.count >= 3) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    public static func matches(_ a: URL, _ b: URL) -> Bool {
        guard let ha = a.host, let hb = b.host,
              let da = registrableDomain(of: ha), let db = registrableDomain(of: hb)
        else { return false }
        return da == db
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
