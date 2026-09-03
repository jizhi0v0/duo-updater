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
/// live on a different domain than the download endpoint. Consequently this gate
/// cannot tell that an otherwise ordinary DNS name resolves to a private address;
/// callers must not describe it as DNS-rebinding protection. It does reject the
/// local names whose destination is defined by their spelling.
public enum ChangelogURLPolicy {

    /// Whether `url` may be handed to a web view.
    ///
    /// Rejects anything but `https` (a plain-text page can be rewritten in
    /// transit), URLs carrying credentials (`https://user:pass@host/` renders a
    /// convincing origin and leaks the pair), IP-literal hosts (no certificate
    /// name to reason about, and no vendor publishes notes at a bare address),
    /// `localhost`/`.localhost` and mDNS `.local` names, and non-standard ports.
    public static func isDisplayable(_ url: URL) -> Bool {
        rejectionReason(url) == nil
    }

    /// Which guard `url` fails, or `nil` when it would pass `isDisplayable`.
    ///
    /// Exists so a caller that refuses a navigation — `WorkbenchWindowView`'s
    /// web-view guardian, in particular — can say *why* instead of just
    /// cancelling. #292: that guardian re-checks every main-frame navigation, not
    /// only the recipe's starting URL, so it can now discover a rejection well
    /// after the pane has already been shown; a plain `Bool` had nothing left to
    /// hand a log line or a user-facing message at that point. Deliberately
    /// categorical rather than including the attacker/vendor-controlled host or
    /// port: those already reach the log line through the caller's own URL
    /// argument (safe there because it goes through a redactor, not straight to
    /// on-screen HTML). #299: an earlier version of this returned that category
    /// as a bare `String`, and a caller put it straight on screen — inside a
    /// signed app that otherwise localizes everything, that string was the one
    /// English literal `check_localizable_keys.py` cannot see, because it never
    /// goes through `String(localized:)`. Returning an enum instead of a string
    /// forces every caller to *choose* a representation rather than reuse
    /// whichever one first came to hand: `RejectionReason.logToken` for a `Log.`
    /// line (fixed English, so it stays grep-able across reports) and
    /// `RejectionReason.localizedDescription` for anything shown to the user.
    /// Neither carries the host or port that triggered the rejection — that
    /// property now lives in the type instead of a comment asking callers to
    /// preserve it by hand.
    ///
    /// Checked in the same order as `isDisplayable`, so the reason reported is
    /// always the same guard that actually rejected the URL.
    public static func rejectionReason(_ url: URL) -> RejectionReason? {
        guard url.scheme?.lowercased() == "https" else { return .notHTTPS }
        guard url.user == nil, url.password == nil else { return .hasCredentials }
        guard let host = url.host, !host.isEmpty else { return .noHost }
        guard !isIPLiteral(host) else { return .ipLiteral }
        guard !isLocalHostname(host) else { return .reservedLocalName }
        if let port = url.port, port != 443 { return .nonStandardPort }
        return nil
    }

    /// Which structural guard rejected a changelog URL. See `rejectionReason`
    /// for why this is a closed set of categories rather than a `String`: no
    /// case here may ever be given an associated value carrying the URL, host,
    /// or port that triggered it — that is the whole point of the type.
    public enum RejectionReason: Sendable, Equatable {
        case notHTTPS
        case hasCredentials
        case noHost
        case ipLiteral
        case reservedLocalName
        case nonStandardPort
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

    /// Names whose local destination follows from the name itself, without a DNS
    /// lookup: RFC 6761 reserves `localhost` and every name below it for loopback.
    /// RFC 6762 §3 gives `.local.` to link-local multicast DNS, but its own
    /// wording is about multi-label names of the form `single-dns-label.local.`
    /// — it never discusses the bare single-label name `local` on its own, so
    /// citing it for that half of this check overstates what it says. The bare
    /// name is refused anyway, on different (and simpler) grounds: no public CA
    /// issues an https certificate for an unqualified single-label name, so
    /// nothing legitimate can ever be reached at `https://local/`, and refusing
    /// it costs no real vendor a changelog page. A trailing root label and case
    /// do not change any of these names. Ordinary domains merely containing
    /// these words (for example `localhost.example.com`) remain displayable.
    static func isLocalHostname(_ host: String) -> Bool {
        let withoutRootLabel = host.count > 1 && host.hasSuffix(".")
            ? String(host.dropLast())
            : host
        let bare = withoutRootLabel.lowercased()
        return bare == "localhost" || bare.hasSuffix(".localhost")
            || bare == "local" || bare.hasSuffix(".local")
    }
}

extension ChangelogURLPolicy.RejectionReason {

    /// Fixed English text for a `Log.` line. Never localized — a log line is
    /// read by whoever has the crash report or the console output open next to
    /// the source, not by the person running the app, and translating it would
    /// break grepping and cross-report comparison (see `Log`'s own doc comment,
    /// and CLAUDE.md). Kept identical to what `rejectionReason` used to return
    /// directly, so an existing log search for these phrases still matches.
    public var logToken: String {
        switch self {
        case .notHTTPS: return "not an https URL"
        case .hasCredentials: return "URL carries credentials"
        case .noHost: return "URL has no host"
        case .ipLiteral: return "host is an IP literal, not a name"
        case .reservedLocalName: return "host is a reserved local-only name"
        case .nonStandardPort: return "non-standard port"
        }
    }

    /// Localized text for the on-screen blocked-notice pane
    /// (`WorkbenchWindowView`'s `WebGuardian.showBlockedNotice`). Translates
    /// only these six fixed categories, never the URL, host, or port that
    /// triggered the rejection — the caller still has to HTML-escape whatever
    /// this returns before handing it to a web view, since a translation can
    /// legitimately contain `&`, `<`, `>`, or a quote mark.
    public var localizedDescription: String {
        switch self {
        case .notHTTPS:
            return String(localized: "This link isn’t secure (it doesn’t use https).")
        case .hasCredentials:
            return String(localized: "This link includes a login that can’t be shown safely.")
        case .noHost:
            return String(localized: "This link has no address to load.")
        case .ipLiteral:
            return String(localized: "This link points at a raw network address instead of a name.")
        case .reservedLocalName:
            return String(localized: "This link points at a local-only name.")
        case .nonStandardPort:
            return String(localized: "This link uses a non-standard port.")
        }
    }
}

extension ChangelogURLPolicy {

    /// Escapes the five characters that are significant inside HTML text
    /// content, for embedding `RejectionReason.localizedDescription` (or the
    /// blocked-notice pane's title) into the hand-built HTML string
    /// `WorkbenchWindowView`'s `WebGuardian` loads in place of a blank
    /// changelog pane. `&` is replaced first so it does not double-escape the
    /// entities this function itself just inserted. Needed because these are
    /// *translated* strings: a fixed English category never contained a quote
    /// mark, but German and French punctuation routinely do, and this pane is
    /// the one place in the app that writes a string into raw HTML rather than
    /// handing it to a `Text` view that escapes on its own.
    public static func htmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
