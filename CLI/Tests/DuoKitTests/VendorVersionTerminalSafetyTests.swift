import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo check` and `duo install` print the version a vendor's endpoint offers,
/// and the CLI-tool rows print a tool's release string. A version-probe regex
/// captures what the response body says, so none of them may reach the
/// terminal with an escape sequence in it (`TerminalText`, as `duo verify`).
@Suite struct VendorVersionTerminalSafetyTests {

    private static let clipboard = "\u{1B}]52;c;ZXZpbA==\u{07}"
    private static let cursor = "\u{1B}[2J\u{1B}[1;1H"

    private static func clean(_ lines: [String]) {
        for line in lines {
            for payload in [clipboard, cursor, "\u{1B}"] {
                #expect(!line.contains(payload), "\(payload.debugDescription) reached the terminal: \(line.debugDescription)")
            }
        }
    }

    /// Mutation: `print(line)` raw again in `Check.emitText`.
    @Test func duoCheckScrubsTheOfferedVersion() throws {
        let row = Check.Row(
            name: "Demo", bundleID: "com.zzfixture.demo", path: "/Applications/Demo.app",
            installedVersion: "1.0", installedBuild: nil,
            latestVersion: "2.0\(Self.clipboard)", latestBuild: nil,
            source: "Vendor", status: "update 2.0",
            hasUpdate: true, hidden: false, route: "vendor")
        var lines: [String] = []
        Check.emitText([row], checked: true, print: { lines.append($0) })
        let line = try #require(lines.first { $0.contains("Demo") })
        #expect(line.contains("Demo  1.0  →  2.0  ["), "\(line)")
        Self.clean(lines)
    }

    /// Mutation: `print(line)` raw again in `CLIToolRows.emitText`.
    @Test func theCommandLineToolRowScrubsTheReleaseString() throws {
        let status = CLIToolRowsTests.status(
            .uv, "/ZZFixture-home/.local/bin/uv", latest: "0.9.9\(Self.cursor)")
        var lines: [String] = []
        CLIToolRows.emitText([CLIToolRows.Row(status)], checked: true, print: { lines.append($0) })
        let line = try #require(lines.first { $0.contains("0.9.9") })
        #expect(line.contains("→  0.9.9  "), "\(line)")
        Self.clean(lines)
    }

    /// Mutation: print the "Will install" line raw again in `Install.describe`.
    @Test func duoInstallScrubsThePlannedVersion() throws {
        let app = InstalledApp(
            name: "Demo", bundleID: "com.zzfixture.demo", shortVersion: "1.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/Demo.app"), isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "2.0\(Self.clipboard)", version: nil, downloadURL: nil,
            sourceName: "Vendor", sourceIdentifier: "demo")
        let item = Install.Planned(
            result: UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2.0")),
            route: .homebrew)
        var lines: [String] = []
        Install.describe([item], refusals: [], print: { lines.append($0) })
        let line = try #require(lines.first { $0.contains("Demo") })
        #expect(line.contains("Demo  1.0  →  2.0  [homebrew]"), "\(line)")
        Self.clean(lines)
    }

    /// The tool lines under "Will install" and "Skipping" carry the same vendor
    /// release string the CLI-tool rows print.
    ///
    /// Mutation: print either tool line raw again in `Install.describe`.
    @Test func duoInstallScrubsTheToolReleaseString() throws {
        let planned = CLIToolRowsTests.status(.uv, "/ZZFixture-home/.local/bin/uv", latest: "0.9.9\(Self.cursor)")
        let refused = CLIToolRowsTests.status(.codex, "/ZZFixture-home/.local/bin/codex", latest: "2.0\(Self.clipboard)")
        var lines: [String] = []
        Install.describe([], refusals: [], tools: [planned],
                         toolRefusals: [(refused, "needs a newer Node", nil)], print: { lines.append($0) })
        #expect(lines.contains { $0.contains("→  0.9.9  /ZZFixture-home/.local/bin/uv") }, "\(lines)")
        #expect(lines.contains { $0.contains("→  2.0  /ZZFixture-home/.local/bin/codex  —  needs a newer Node") }, "\(lines)")
        Self.clean(lines)
    }
}
