import Foundation
import Testing
@testable import DuoUpdaterCore

/// UTM's bundle has no local Beta marker. These tests exercise the full source
/// path that proves the installed tag's channel from GitHub, then resolves the
/// newest release and notes from that same train.
@Suite(.serialized)
struct UTMGitHubChannelTests {
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let path = request.url?.path ?? ""
            let body: String
            let status: Int
            switch path {
            case "/repos/utmapp/UTM/releases/tags/v5.0.4":
                status = 200
                body = Self.release(tag: "v5.0.4", prerelease: true, body: "Installed Beta")
            case "/repos/utmapp/UTM/releases/tags/v4.7.4":
                status = 200
                body = Self.release(tag: "v4.7.4", prerelease: false, body: "Installed Stable")
            case "/repos/utmapp/UTM/releases/tags/v5.0.3":
                status = 200
                // A schema drift must not turn "unknown" into Stable.
                body = """
                {
                  "tag_name":"v5.0.3",
                  "published_at":"2026-08-01T00:00:00Z",
                  "assets":[]
                }
                """
            case "/repos/utmapp/UTM/releases/latest":
                status = 200
                body = Self.release(
                    tag: "v4.7.5", prerelease: false,
                    body: "## Changes (v4.7.5)\n* Stable-only QEMU update")
            case "/repos/utmapp/UTM/releases":
                status = 200
                // A future Stable release is deliberately first. The Beta rule
                // must filter on `prerelease`, not merely take the list head.
                body = "[" + Self.release(
                    tag: "v6.0.0", prerelease: false,
                    body: "## Changes (v6.0.0)\n* Stable-only future change")
                    + "," + Self.release(
                        tag: "v5.0.5", prerelease: true,
                        body: "## Changes (v5.0.5)\n* Beta-only DirectX update")
                    + "]"
            default:
                status = 404
                body = #"{"message":"Not Found"}"#
            }

            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func release(tag: String, prerelease: Bool, body: String) -> String {
            let escapedBody = body
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return """
            {
              "tag_name":"\(tag)",
              "prerelease":\(prerelease),
              "draft":false,
              "published_at":"2026-09-02T05:14:37Z",
              "html_url":"https://github.com/utmapp/UTM/releases/tag/\(tag)",
              "body":"\(escapedBody)",
              "assets":[{
                "name":"UTM.dmg",
                "browser_download_url":"https://github.com/utmapp/UTM/releases/download/\(tag)/UTM.dmg",
                "size":302621893
              }]
            }
            """
        }
    }

    private func source() -> GitHubReleasesSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == "com.utmapp.UTM" }
        return GitHubReleasesSource(
            rules: rules, session: URLSession(configuration: configuration))
    }

    private func app(version: String) -> InstalledApp {
        InstalledApp(
            name: "UTM", bundleID: "com.utmapp.UTM",
            shortVersion: version, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/UTM.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    @Test func directBetaUsesThePrereleaseRuleInstallerAndNotes() async throws {
        let candidate = try await source().latestVersion(for: app(version: "5.0.4"))
        let remote = try #require(candidate)

        #expect(remote.displayVersion == "5.0.5")
        #expect(remote.releaseChannel == .beta)
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.requiresManualInstaller == false)
        #expect(remote.downloadURL?.absoluteString
                == "https://github.com/utmapp/UTM/releases/download/v5.0.5/UTM.dmg")
        #expect(remote.releaseHistory.map(\.version) == ["5.0.5"])
        #expect(UpdateResult(
            app: app(version: "5.0.4"), remote: remote,
            status: .updateAvailable(latest: "5.0.5")
        ).effectiveReleaseChannel == .beta)
        let items = try #require(remote.structuredChangelog?.entries.first?.items)
        #expect(items.contains { $0.contains("Beta-only DirectX update") })
        #expect(!items.contains { $0.contains("Stable-only") })
    }

    @Test func directStableUsesTheStableRuleAndNotes() async throws {
        let candidate = try await source().latestVersion(for: app(version: "4.7.4"))
        let remote = try #require(candidate)

        #expect(remote.displayVersion == "4.7.5")
        #expect(remote.releaseChannel == .stable)
        #expect(remote.vendorInstallerKind == .dmg)
        let items = try #require(remote.structuredChangelog?.entries.first?.items)
        #expect(items.contains { $0.contains("Stable-only QEMU update") })
        #expect(!items.contains { $0.contains("Beta-only") })
    }

    @Test func anUnknownInstalledTagFailsClosedInsteadOfGuessingStable() async throws {
        let remote = try await source().latestVersion(for: app(version: "9.9.9-local"))
        #expect(remote == nil)
    }

    @Test func missingReleaseStateFailsClosedInsteadOfMeaningStable() async throws {
        let remote = try await source().latestVersion(for: app(version: "5.0.3"))
        #expect(remote == nil)
    }
}
