import Foundation

/// One scrubber for every string that leaves the verifier's process — report
/// files, issue bodies, LLM payloads, stdout, logs.
///
/// The reason it is a single choke point rather than a rule applied at each
/// call site: an automated sweep's whole job is to take vendor responses and
/// *publish* them, into a GitHub issue or a model prompt. Every one of those
/// exits is a chance to leak something the app holds legitimately — a licensed
/// appcast URL with the key in the query string, a bearer token in a header.
/// A rule that has to be remembered per call site is a rule that will be
/// forgotten at one of them.
///
/// This is deliberately over-eager. Losing a checksum out of a body sample costs
/// nothing; a license key in a public issue can't be taken back.
public enum Redactor {

    public static let placeholder = "«redacted»"

    /// Query-parameter names whose *values* never leave the process. Matched
    /// case-insensitively against both the exact name and any name containing
    /// one of these, so `api_key`, `licenseKey` and `X-Auth-Sig` all land.
    static let sensitiveParameterNames = [
        "key", "token", "license", "auth", "sig", "signature",
        "access_token", "instance", "api_key", "apikey", "secret",
        "password", "pwd", "session", "credential",
        // Rollout identifiers. These grant nothing, which is why a recipe may
        // send one (see `ProbeIdentity`) — but they identify a machine, and the
        // contract that they never appear in a log, a report or a public issue
        // rested entirely on the resolved URL never leaving the fetch. That is
        // one layer with nothing behind it; these put the net back under it.
        "installation_id", "installationid", "device_id", "deviceid",
    ]

    /// Header names dropped whole — the value *is* the secret.
    static let sensitiveHeaderNames = ["authorization", "cookie", "set-cookie", "proxy-authorization"]

    /// Shapes worth scrubbing wherever they appear, even outside a URL.
    ///
    /// The long-hex rule also eats legitimate SHA-256/512 digests out of body
    /// samples. That is the intended trade: a digest is never what you need to
    /// repair a version pattern, and "32+ hex characters" is exactly what an
    /// opaque license key looks like too.
    private static let secretPatterns: [String] = [
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,                       // GitHub tokens
        #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,         // JWTs
        #"sk-ant-[A-Za-z0-9_-]{20,}"#,                         // Anthropic keys
        #"\b[A-Fa-f0-9]{32,}\b"#,                              // opaque hex blobs
        #"(?is)<script\b[^>]*>.*?</script>"#,                  // inline JS
    ]

    /// Scrub a URL for display: keep scheme, host and path; replace the value of
    /// any sensitive query item. The path is kept because that's usually where
    /// the version lives — which is the whole point of showing the URL at all.
    public static func url(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return text(url.absoluteString)
        }
        if let items = components.queryItems {
            components.queryItems = items.map { item in
                isSensitive(item.name)
                    ? URLQueryItem(name: item.name, value: placeholder)
                    : item
            }
        }
        return text(components.url?.absoluteString ?? url.absoluteString)
    }

    /// The host alone, for the cases where even a path could carry an identifier.
    public static func host(_ url: URL) -> String { url.host ?? "«unknown host»" }

    public static func headers(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [:]) { out, pair in
            out[pair.key] = sensitiveHeaderNames.contains(pair.key.lowercased())
                ? placeholder
                : text(pair.value)
        }
    }

    /// Scrub free text: `name=value` pairs with a sensitive name, then every
    /// known secret shape. Optionally cap the length.
    public static func text(_ input: String, limit: Int? = nil) -> String {
        var out = input

        // `key=…` / `token: …` inside a URL, a query string, or a log line. Stops
        // at the delimiters that end a value in any of those contexts.
        let assignment = "(?i)\\b(" + sensitiveParameterNames
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
            + ")([A-Za-z_-]*)\\s*[=:]\\s*[^&\\s\"'<>,}]+"
        out = replace(out, pattern: assignment, with: "$1$2=\(placeholder)")

        for pattern in secretPatterns {
            out = replace(out, pattern: pattern, with: placeholder)
        }

        if let limit, out.count > limit {
            out = String(out.prefix(limit)) + "…[truncated]"
        }
        return out
    }

    private static func isSensitive(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return sensitiveParameterNames.contains { lowered.contains($0) }
    }

    private static func replace(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input, range: NSRange(input.startIndex..., in: input), withTemplate: template)
    }
}
