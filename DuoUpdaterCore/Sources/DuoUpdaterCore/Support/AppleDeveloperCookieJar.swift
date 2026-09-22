import Foundation

/// Encodes and decodes the cookies that back an Apple Developer web session, so
/// the app can save them to the Keychain (`Data`) and restore them into a
/// `WKWebsiteDataStore` (`[HTTPCookie]`) across launches — WebKit itself drops the
/// session-only ones (`myacinfo`, in particular) the moment the process quits.
///
/// Pure Foundation: no WebKit import, so it can be unit-tested with `swift test`
/// rather than needing a host process and a real web view.
public enum AppleDeveloperCookieJar {
    /// Only cookies for this domain and its subdomains are kept — the sign-in
    /// session lives entirely under apple.com, and nothing else belongs in this
    /// jar even if a caller handed us a mixed bag.
    private static let allowedDomainSuffix = "apple.com"

    /// Encode `cookies` (already filtered by the caller, or not — this filters
    /// again) as a property list of `HTTPCookie.properties`. Foreign-domain
    /// cookies are dropped silently rather than rejected, so a caller can hand
    /// this the whole store's cookies without pre-filtering.
    public static func encode(_ cookies: [HTTPCookie]) -> Data {
        let plists: [[String: Any]] = cookies.compactMap { cookie in
            guard isAppleDomain(cookie.domain) else { return nil }
            guard let properties = cookie.properties else { return nil }
            // `HTTPCookiePropertyKey` isn't directly plist-safe (NSExpiresDate can
            // be a Date, which IS plist-safe, but the dictionary's key type is
            // the custom RawRepresentable wrapper) — restring the keys.
            var plist: [String: Any] = [:]
            for (key, value) in properties {
                plist[key.rawValue] = value
            }
            return plist
        }
        return (try? PropertyListSerialization.data(
            fromPropertyList: plists, format: .binary, options: 0)) ?? Data()
    }

    /// Decode `data` back into cookies, keeping only `*.apple.com` domains.
    /// Corrupt or unreadable data yields an empty array rather than throwing —
    /// callers treat "no session" and "unreadable session" the same way (sign in
    /// again), so there's nothing a caller would do differently for either.
    public static func decode(_ data: Data) -> [HTTPCookie] {
        guard !data.isEmpty,
              let plists = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [[String: Any]]
        else { return [] }
        return plists.compactMap { plist in
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in plist {
                properties[HTTPCookiePropertyKey(key)] = value
            }
            guard let cookie = HTTPCookie(properties: properties) else { return nil }
            guard isAppleDomain(cookie.domain) else { return nil }
            return cookie
        }
    }

    private static func isAppleDomain(_ domain: String) -> Bool {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == allowedDomainSuffix || host.hasSuffix("." + allowedDomainSuffix)
    }
}
