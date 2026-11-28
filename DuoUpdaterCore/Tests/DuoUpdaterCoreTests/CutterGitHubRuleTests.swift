import Foundation
import Testing
@testable import DuoUpdaterCore

struct CutterGitHubRuleTests {
    private final class Feed: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let url = request.url!
            let latest = "/repos/rizinorg/cutter/releases/latest"
            let list = "/repos/rizinorg/cutter/releases"
            let stable = Self.release("v2.5.0", prerelease: false)
            let intelOnly = Self.release("v2.6.0", prerelease: false, hasArm64: false)
            let body: String
            switch url.path {
            case latest:
                body = intelOnly
            case list:
                body = """
                [
                  \(Self.release("v5.0.0-rc1", prerelease: true)),
                  \(intelOnly),
                  \(Self.release("v2.4.1", prerelease: false)),
                  \(stable)
                ]
                """
            default:
                Issue.record("unexpected URL \(url)")
                body = "{}"
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        // Trimmed from the vendor's v2.5.0 response. Fallback carries an RC
        // and lists a lower stable version first.
        private static func release(_ tag: String, prerelease: Bool, hasArm64: Bool = true) -> String {
            let base = "https://github.com/rizinorg/cutter/releases/download/\(tag)/Cutter-\(tag)-macOS"
            let arm64 = hasArm64 ? """
                ,{ "name": "Cutter-\(tag)-macOS-arm64.dmg", "browser_download_url": "\(base)-arm64.dmg" }
                """ : ""
            return """
            {
              "tag_name": "\(tag)", "prerelease": \(prerelease), "draft": false,
              "published_at": "2026-06-30T18:37:00Z",
              "html_url": "https://github.com/unrelated/cutter/releases/tag/\(tag)",
              "body": "- Use [Rizin v0.9.1](https://github.com/rizinorg/rizin/releases/tag/v0.9.1)",
              "assets": [
                { "name": "Cutter-\(tag)-macOS-x86_64.dmg", "browser_download_url": "\(base)-x86_64.dmg" },
                { "name": "Cutter-v9.0.0-macOS-arm64.dmg", "browser_download_url": "https://github.com/rizinorg/cutter/releases/download/\(tag)/Cutter-v9.0.0-macOS-arm64.dmg" },
                { "name": "Cutter-\(tag)-macOS-arm64.dmg", "browser_download_url": "https://github.com/rizinorg/cutter/releases/download/v2.3.4/Cutter-v2.3.4-macOS-arm64.dmg" }
                \(arm64)
              ]
            }
            """
        }
    }

    private func app(_ version: String) -> InstalledApp {
        let bundleID = "re.rizin.cutter"
        return InstalledApp(
            name: "Cutter", bundleID: bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/Cutter.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: ReleaseChannel.detect(
                name: "Cutter", bundleID: bundleID, keystoneChannel: nil, version: version))
    }

    @Test func cutterOffersOnlyHigherStableVersions() async throws {
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == "re.rizin.cutter" }
        let rule = try #require(rules.first)
        #expect(rules.count == 1)
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(VendorProbeRecipe.extractVersion(from: "v5.0.0-rc1", pattern: rule.versionPattern) == nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Feed.self]
        let source = GitHubReleasesSource(
            rules: rules, token: "fixture-token", session: URLSession(configuration: configuration))
        let older = app("2.4.0-HEAD-ec6a6fb")
        let remote = try #require(try await source.latestVersion(for: older))

        #expect(remote.releaseChannel == .stable)
        #expect(remote.shortVersion == "2.5.0")
        #expect(remote.downloadURL?.absoluteString ==
            "https://github.com/rizinorg/cutter/releases/download/v2.5.0/Cutter-v2.5.0-macOS-arm64.dmg")
        #expect(remote.pageURL?.absoluteString == "https://github.com/rizinorg/cutter/releases/tag/v2.5.0")
        #expect(remote.vendorInstallerKind == .dmg && remote.installTrust == .developerID)
        #expect(remote.requiresExactPackageVersion)
        #expect(remote.releaseHistory.map(\.version) == ["2.5.0", "2.4.1"])
        #expect(remote.structuredChangelog?.entries.first?.version == "2.5.0")
        #expect(UpdateChecker.evaluate(installed: older, remote: remote) == .updateAvailable(latest: "2.5.0"))

        for version in ["2.5.0-HEAD-a6f6ad7", "2.5.0-HEAD-2f053dd", "5.0.0-HEAD-e1bcdef"] {
            #expect(UpdateChecker.evaluate(installed: app(version), remote: remote) == .upToDate)
        }
        let brew = RemoteVersion(shortVersion: "2.5.0", version: nil, downloadURL: nil, sourceName: "Homebrew")
        #expect(UpdateChecker.evaluate(installed: app("2.5.0-HEAD-a6f6ad7"), remote: brew) == .upToDate)
    }
}
