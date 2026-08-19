import Foundation

/// What a changelog URL must look like before it is loaded in a web view.
///
/// Release-note URLs come from recipes, and a recipe's `changelogURL` is the one
/// field that ends up as an attacker-choosable origin rendered in-process, next
/// to a window that holds credentials for other services. Today every recipe is
/// compiled into the signed binary, so this is defence in depth rather than a
/// live hole — but it is the field most likely to be served remotely first, and
/// the check costs nothing to have in place before that happens.
///
/// The rules are deliberately structural, not an allowlist of hosts: a per-recipe
/// host binding only becomes meaningful once recipes stop being compiled in, and
/// guessing at vendor domains now would break legitimate documentation sites that
/// live on a different domain than the download endpoint.
public enum ChangelogURLPolicy {

    /// Whether `url` may be handed to a web view.
    ///
    /// Rejects anything but `https` (a plain-text page can be rewritten in
    /// transit), URLs carrying credentials (`https://user:pass@host/` renders a
    /// convincing origin and leaks the pair), IP-literal hosts (no certificate
    /// name to reason about, and no vendor publishes notes at a bare address),
    /// and non-standard ports.
    public static func isDisplayable(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard url.user == nil, url.password == nil else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        guard !isIPLiteral(host) else { return false }
        if let port = url.port, port != 443 { return false }
        return true
    }

    /// `url` when it passes, `nil` when it does not — so a caller can fall through
    /// to whatever it shows when there are no notes.
    public static func displayable(_ url: URL?) -> URL? {
        guard let url, isDisplayable(url) else { return nil }
        return url
    }

    /// IPv4 dotted-quad, or IPv6 in either spelling. `URL.host` strips the
    /// brackets off an IPv6 literal, so the colon is the reliable signal — and a
    /// colon cannot appear in a hostname, so this does not catch a legitimate
    /// vendor domain.
    static func isIPLiteral(_ host: String) -> Bool {
        if host.hasPrefix("[") || host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }
}
