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

    /// IPv6 in either spelling, or any IPv4 spelling the web view will resolve.
    /// `URL.host` strips the brackets off an IPv6 literal, so the colon is the
    /// reliable signal — and a colon cannot appear in a hostname, so this does
    /// not catch a legitimate vendor domain. The bracket test is belt-and-braces
    /// for a caller that hands over a raw authority instead of `URL.host`.
    ///
    /// IPv4 is decided by `inet_aton`, not by counting dot-parts. `2130706433`,
    /// `0x7f000001`, `127.1` and `0177.0.0.1` are all 127.0.0.1 to the networking
    /// stack the web view uses, and only the last of them has four parts; a
    /// dotted-quad check let the other three through. `inet_pton(AF_INET)` is not
    /// a substitute — it accepts dotted-quad only and would reopen the same hole
    /// — where `inet_aton` is the classic BSD parser that takes the decimal, hex,
    /// octal and 1-/2-/3-part forms.
    ///
    /// **The trailing dot is stripped first, and that is load-bearing.** WebKit
    /// parses a host by the WHATWG URL rules, which drop one trailing empty label
    /// before deciding whether the rest is an address; `inet_aton` does not, and
    /// refuses every spelling the moment a dot is appended. Without this strip,
    /// `https://127.0.0.1./`, `https://2130706433./` and `https://127.1./` all
    /// pass the gate and then load 127.0.0.1 — measured with a real `WKWebView`,
    /// which rewrites its own `URL` to `http://127.0.0.1:8931/` for each of them,
    /// and with `curl`, which reaches `remote_ip=127.0.0.1` for all three.
    /// One dot only: `1..1` has an empty label that is not last, which is a
    /// parse failure for WebKit too, so it stays a hostname here.
    ///
    /// Two ways `inet_aton` and WebKit still disagree, both **fail-closed** — this
    /// refuses a little more than WebKit resolves, never less:
    ///   - `inet_aton` stops at the first whitespace byte and ignores the rest, so
    ///     `"127.0.0.1 evil.com"` parses as an address. `URL.host` can produce that
    ///     from `https://127.0.0.1%20evil.com/`, and refusing it is the safe answer.
    ///   - it wraps instead of range-checking, so `4294967296` and
    ///     `999999999999999999999` parse, where WebKit calls the URL invalid.
    /// A hostname cannot slip through either way: a letter that is not part of a
    /// `0x` prefix ends the parse with trailing garbage, which `inet_aton` rejects,
    /// so `1.2.3.example.com` and `1e3` still read as domains.
    static func isIPLiteral(_ host: String) -> Bool {
        if host.hasPrefix("[") || host.contains(":") { return true }
        // One trailing empty label, the way the WHATWG host parser drops it.
        let bare = host.count > 1 && host.hasSuffix(".") ? String(host.dropLast()) : host
        var address = in_addr()
        return inet_aton(bare, &address) != 0
    }
}
