import Foundation

/// Translates the macOS system proxy settings into the `*_proxy` environment
/// variables command-line tools expect.
///
/// Why this exists: our own network goes through `URLSession`, which reads the
/// system proxy configuration automatically. Subprocesses do not. `brew` shells
/// out to `curl`, and **curl ignores the macOS system proxy** — it only reads
/// `http_proxy` / `https_proxy` / `all_proxy` from its environment (`man brew`,
/// ENVIRONMENT: "Use this HTTPS proxy for curl(1), git(1) and svn(1) when
/// downloading through Homebrew").
///
/// A GUI app launched from Finder inherits `launchd`'s environment, which has no
/// proxy variables — a shell's `~/.zshrc` exports never reach it. So on a machine
/// that reaches the network only through a proxy, every app download worked while
/// `brew upgrade` died with `curl: (28) Failed to connect` — the same command that
/// succeeds in the user's terminal, where the exports are present.
///
/// Not covered: proxy auto-config (PAC) and auto-discovery (WPAD), which have no
/// environment-variable equivalent — a PAC-only setup still can't be handed to
/// curl, and is left alone rather than guessed at.
enum SystemProxyEnvironment {

    /// `env` with proxy variables filled in from the system settings.
    ///
    /// Never overwrites a variable the caller already has: if the app *was*
    /// launched from a shell that exported `https_proxy`, that explicit choice
    /// wins over the system pane.
    static func applied(
        to env: [String: String],
        settings: [String: Any]? = currentSettings()
    ) -> [String: String] {
        guard let settings else { return env }
        var env = env
        let alreadySet = Set(env.keys.map { $0.lowercased() })
        for (key, value) in variables(from: settings) where !alreadySet.contains(key) {
            env[key] = value
        }
        return env
    }

    /// The live system proxy configuration, or nil when it can't be read.
    static func currentSettings() -> [String: Any]? {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
    }

    /// The lowercase `*_proxy` variables implied by a system proxy dictionary.
    ///
    /// Lowercase because that's what `man brew` documents and what curl reads for
    /// every protocol (curl deliberately ignores an uppercase `HTTP_PROXY`, since
    /// a CGI request header could forge it).
    static func variables(from settings: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]

        if let http = endpoint(settings, enable: "HTTPEnable", host: "HTTPProxy", port: "HTTPPort") {
            out["http_proxy"] = "http://\(http)"
        }
        if let https = endpoint(settings, enable: "HTTPSEnable", host: "HTTPSProxy", port: "HTTPSPort") {
            // Still `http://`: an HTTPS proxy is an HTTP CONNECT proxy, and
            // `https://` would tell curl to speak TLS *to the proxy itself*.
            out["https_proxy"] = "http://\(https)"
        }
        // SOCKS is a fallback, not an addition: `all_proxy` covers protocols with
        // no specific proxy, so it only helps where http/https left a gap. Setting
        // it alongside them would just add a second path to get wrong.
        if out.isEmpty,
            let socks = endpoint(settings, enable: "SOCKSEnable", host: "SOCKSProxy", port: "SOCKSPort")
        {
            out["all_proxy"] = "socks5://\(socks)"
        }

        guard !out.isEmpty else { return [:] }
        out["no_proxy"] = noProxy(settings)
        return out
    }

    /// `host:port` for one proxy protocol, or nil when it's off or incomplete.
    private static func endpoint(
        _ settings: [String: Any], enable: String, host: String, port: String
    ) -> String? {
        guard
            (settings[enable] as? Int) == 1,
            let host = settings[host] as? String, !host.isEmpty
        else { return nil }
        guard let port = settings[port] as? Int, port > 0 else { return host }
        return "\(host):\(port)"
    }

    /// The bypass list: loopback always, plus whatever the user excepted.
    ///
    /// `*.example.com` becomes `.example.com` — curl matches a bare leading dot as
    /// a domain suffix and doesn't understand the glob. CIDR entries are passed
    /// through as-is; curl won't match them, but a proxy that can't reach a private
    /// range is a configuration the user already lives with in their shell.
    private static func noProxy(_ settings: [String: Any]) -> String {
        var entries = ["localhost", "127.0.0.1", "::1"]
        for entry in (settings["ExceptionsList"] as? [String]) ?? [] {
            let cleaned = entry.hasPrefix("*") ? String(entry.dropFirst()) : entry
            guard !cleaned.isEmpty, !entries.contains(cleaned) else { continue }
            entries.append(cleaned)
        }
        return entries.joined(separator: ",")
    }
}

extension ProcessInfo {
    /// The current environment with the system proxy settings folded in — the
    /// starting point for every `brew` subprocess we spawn. See
    /// `SystemProxyEnvironment` for why a GUI app has to do this by hand.
    var environmentWithSystemProxy: [String: String] {
        SystemProxyEnvironment.applied(to: environment)
    }
}
