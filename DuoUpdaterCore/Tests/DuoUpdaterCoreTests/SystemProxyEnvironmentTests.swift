import Testing
import Foundation
@testable import DuoUpdaterCore

/// `brew upgrade` failed with `curl: (28) Failed to connect` on a machine whose
/// only route out is a local proxy, while the same command succeeded in the user's
/// terminal. Cause: a Finder-launched GUI app inherits launchd's environment, which
/// has no `*_proxy` exports, and curl — unlike `URLSession` — never reads the macOS
/// system proxy settings. These pin the translation from the system dictionary to
/// the variables brew hands curl.
@Suite struct SystemProxyEnvironmentTests {

    /// The reported machine's settings: HTTP + HTTPS through one local proxy.
    private let httpSettings: [String: Any] = [
        "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 6152,
        "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 6152,
        "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 6153,
        "ExceptionsList": ["*.baidu.com", "192.168.0.0/24"],
    ]

    @Test func translatesEnabledHTTPAndHTTPSProxies() {
        let vars = SystemProxyEnvironment.variables(from: httpSettings)
        #expect(vars["http_proxy"] == "http://127.0.0.1:6152")
        // `http://`, not `https://`: an HTTPS proxy is an HTTP CONNECT proxy.
        #expect(vars["https_proxy"] == "http://127.0.0.1:6152")
        // SOCKS is a fallback only — it must not shadow the configured pair.
        #expect(vars["all_proxy"] == nil)
    }

    @Test func bypassListKeepsLoopbackAndDeglobsDomains() {
        let bypass = SystemProxyEnvironment.variables(from: httpSettings)["no_proxy"] ?? ""
        let entries = bypass.split(separator: ",").map(String.init)
        #expect(entries.contains("localhost"))
        #expect(entries.contains("127.0.0.1"))
        // curl matches a leading dot as a suffix; it doesn't understand `*.`.
        #expect(entries.contains(".baidu.com"))
        #expect(!entries.contains("*.baidu.com"))
    }

    @Test func usesSOCKSOnlyWhenNoHTTPProxyIsConfigured() {
        let vars = SystemProxyEnvironment.variables(from: [
            "HTTPEnable": 0, "HTTPSEnable": 0,
            "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 6153,
        ])
        #expect(vars["all_proxy"] == "socks5://127.0.0.1:6153")
        #expect(vars["http_proxy"] == nil)
    }

    /// A disabled pane must stay disabled — no variables at all, so brew behaves
    /// exactly as it does today on a direct connection.
    @Test func emitsNothingWhenAllProxiesAreOff() {
        let vars = SystemProxyEnvironment.variables(from: [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            "HTTPProxy": "127.0.0.1", "HTTPPort": 6152,
        ])
        #expect(vars.isEmpty)
    }

    /// Incomplete entries (enabled with no host) must not produce a broken
    /// `http://:6152` that would break downloads that work today.
    @Test func ignoresEnabledProxyWithoutAHost() {
        let vars = SystemProxyEnvironment.variables(from: ["HTTPEnable": 1, "HTTPPort": 6152])
        #expect(vars.isEmpty)
    }

    @Test func appliesToEnvironmentWithoutOverwritingExplicitExports() {
        let env = SystemProxyEnvironment.applied(
            to: ["PATH": "/usr/bin", "https_proxy": "http://shell.example:8080"],
            settings: httpSettings)
        // A shell's own export wins over the system pane.
        #expect(env["https_proxy"] == "http://shell.example:8080")
        // …but the gap it left is still filled.
        #expect(env["http_proxy"] == "http://127.0.0.1:6152")
        #expect(env["PATH"] == "/usr/bin")
    }

    /// The one shape where "an explicit export wins" costs something, pinned so
    /// the cost is visible rather than discovered.
    ///
    /// `applied` compares names case-insensitively, and `man curl` (ENVIRONMENT)
    /// says `http_proxy` "is an exception as it is only available in lower case"
    /// while every other proxy variable is read in either case. So an inherited
    /// `HTTPS_PROXY` genuinely is the user's choice and rightly blocks ours — but
    /// an inherited `HTTP_PROXY` is read by nobody, and blocking `http_proxy`
    /// leaves curl with no HTTP proxy at all.
    ///
    /// Asserted, not fixed: see `applied`'s doc comment for why filling the
    /// lowercase key from the system pane is the worse trade. If that decision is
    /// ever revisited, this is the test that changes.
    @Test func upperCaseHTTPProxyBlocksTheLowerCaseKey() {
        let env = SystemProxyEnvironment.applied(
            to: ["HTTP_PROXY": "http://shell.example:8080"], settings: httpSettings)
        #expect(env["HTTP_PROXY"] == "http://shell.example:8080")
        #expect(env["http_proxy"] == nil)
        // The same fold on a variable curl *does* read in either case is simply
        // correct, which is why the rule is not wrong in general.
        let https = SystemProxyEnvironment.applied(
            to: ["HTTPS_PROXY": "http://shell.example:8080"], settings: httpSettings)
        #expect(https["https_proxy"] == nil)
        // And an untaken name is still filled in both cases.
        #expect(env["https_proxy"] == "http://127.0.0.1:6152")
    }

    @Test func leavesEnvironmentUntouchedWhenSettingsAreUnreadable() {
        let env = SystemProxyEnvironment.applied(to: ["PATH": "/usr/bin"], settings: nil)
        #expect(env == ["PATH": "/usr/bin"])
    }

    // MARK: - What a command-line-tool updater's child inherits

    /// A token exported for `gh` must not ride into a vendor's installer script.
    /// Kills: leaving either name in; dropping other variables with them.
    @Test func theChildEnvironmentDropsOnlyTheGitHubTokens() {
        let env = SystemProxyEnvironment.withoutGitHubTokens([
            "GH_TOKEN": "ZZFixture-gh", "GITHUB_TOKEN": "ZZFixture-github",
            "PATH": "/usr/bin", "https_proxy": "http://127.0.0.1:6152",
            "GITHUB_ACCESS_TOKEN": "ZZFixture-bun-own", "UV_GITHUB_TOKEN": "ZZFixture-uv-own",
        ])
        #expect(env == [
            "PATH": "/usr/bin", "https_proxy": "http://127.0.0.1:6152",
            "GITHUB_ACCESS_TOKEN": "ZZFixture-bun-own", "UV_GITHUB_TOKEN": "ZZFixture-uv-own",
        ])
    }

    /// No updater or provider under `CLITools` builds its child's environment from
    /// the full one. Source-level because the 31 default closures are not
    /// reachable from a test without running a vendor's tool; the one exception is
    /// the administrator runner, whose script takes the proxy variables by name
    /// (`CLIToolAdministratorRun.proxies`) and nothing else.
    /// Kills: a new updater copying the old line; reverting one of the 31.
    @Test func noCLIToolChildInheritsTheFullEnvironment() throws {
        let tools = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DuoUpdaterCore/CLITools", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(
            at: tools, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        try #require(files.count > 100, "the CLITools sources were not found at \(tools.path)")
        var inheriting: [String] = []
        var scrubbed = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("childEnvironmentWithSystemProxy") { scrubbed += 1 }
            if text.contains("processInfo.environmentWithSystemProxy") { inheriting.append(file.lastPathComponent) }
        }
        #expect(inheriting == ["CLIToolAdministratorRun.swift"], "\(inheriting)")
        #expect(scrubbed == 31)
    }
}
