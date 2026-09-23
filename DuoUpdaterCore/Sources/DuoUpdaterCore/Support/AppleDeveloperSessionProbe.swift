import Foundation

/// Asks Apple whether a saved Apple Developer session is still signed in, by
/// reading where the authorized download endpoint *would* send us — without
/// going there.
///
/// Apple publishes no lifetime for the session (`myacinfo`), and nothing in the
/// cookie, local storage or `/services-session/v1/info` says when it ends
/// (2026-09-22). The only honest answer is to ask. `services-account/download`
/// answers with a redirect either way (measured 2026-09-22):
///  - signed in → `download.developer.apple.com/Developer_Tools/…` (the CDN);
///  - signed out → `idmsa.apple.com/IDMSWebAuth/signin…`.
/// Not following it keeps the check to one small request: no archive bytes are
/// fetched, and the CDN is never touched.
///
/// Pure Foundation, so the verdict is unit-testable without a network.
public enum AppleDeveloperSessionProbe {
    public enum Verdict: Sendable, Equatable {
        case signedIn
        case expired
        /// Anything else — a network error, a proxy page, a status or host this
        /// was never measured against. Says nothing about the session, so the
        /// caller keeps whatever it knew before.
        case inconclusive
    }

    /// An old GA archive, chosen because it is listed and stable: the check
    /// only reads the redirect, so which file it names does not matter as long
    /// as Apple keeps it (Xcode 16.4, from the xcodereleases index).
    public static let probeURL = URL(
        string: "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_16.4/Xcode_16.4.xip")!

    /// The names of the cookies one response sets, sorted, never their values —
    /// for the log that tells whether a check hands out a new `myacinfo` (and so
    /// keeps the session alive by itself) or not. A cookie the response deletes
    /// is marked `-name`: an expiry already past, or an empty value.
    ///
    /// `now` defaults to after parsing, not before: `Max-Age=0` parses to the
    /// moment of parsing, floored to the second (measured 2026-09-23), so a clock
    /// read before it could fall on the far side of a second boundary.
    public static func setCookieNames(
        headerFields: [String: String], url: URL = probeURL, now: Date? = nil
    ) -> [String] {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        let now = now ?? Date()
        return cookies
            .map { cookie in
                let expired = cookie.expiresDate.map { $0 <= now } ?? false
                return expired || cookie.value.isEmpty ? "-" + cookie.name : cookie.name
            }
            .sorted()
    }

    /// The verdict for one unfollowed response.
    public static func verdict(status: Int, location: String?) -> Verdict {
        guard (300..<400).contains(status),
              let location,
              let host = URL(string: location, relativeTo: probeURL)?.host?.lowercased()
        else { return .inconclusive }
        if host == "download.developer.apple.com" { return .signedIn }
        if host == "idmsa.apple.com" { return .expired }
        return .inconclusive
    }
}
