import Foundation
import Testing
@testable import DuoUpdaterCore

/// Shotcut's prereleases carry nothing local: same id, Team, asset names and a
/// plain version. The beta rule proves a copy's track from GitHub's
/// `prerelease` bit on its exact tag, then offers the newest release of any
/// kind. The fixture's tags and bits are real (`v26.10.30` prerelease,
/// `v26.9.27` stable carrying the 26.9.28 respin, 2026-11-11); `v26.11.6` and
/// `v26.11.20` are made up, to show the next prerelease and the stable after it.
@Suite(.serialized)
struct ShotcutBetaChannelTests {
    private static let id = "com.Meltytech.Shotcut"

    /// What the release list holds for each test, newest first.
    nonisolated(unsafe) static var list: [String] = []

    private final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        static let releases: [String: (prerelease: Bool, assets: [String])] = [
            "v26.11.20": (false, ["shotcut-macos-26.11.20.dmg"]),
            "v26.11.6": (true, ["shotcut-macos-26.11.6.dmg", "shotcut-macos-unsigned-26.11.6.dmg"]),
            "v26.10.30": (true, ["shotcut-macos-26.10.30.dmg", "shotcut-macos-unsigned-26.10.30.dmg"]),
            "v26.9.27": (false, ["shotcut-macos-26.9.27.dmg", "shotcut-macos-26.9.28.dmg"]),
        ]

        static func json(_ tag: String) -> String {
            let r = releases[tag]!
            let assets = r.assets.map {
                #"{"name":"\#($0)","browser_download_url":"https://github.com/mltframework/shotcut/releases/download/\#(tag)/\#($0)","size":1000}"#
            }
            return """
            {"tag_name":"\(tag)","draft":false,"prerelease":\(r.prerelease),\
            "published_at":"2026-10-30T00:00:00Z",\
            "html_url":"https://github.com/mltframework/shotcut/releases/tag/\(tag)",\
            "body":"- Notes for \(tag)","assets":[\(assets.joined(separator: ","))]}
            """
        }

        override func startLoading() {
            let path = request.url?.path ?? ""
            let prefix = "/repos/mltframework/shotcut/releases"
            var status = 200
            let body: String
            if path == prefix + "/latest" {
                let tag = ShotcutBetaChannelTests.list.first { !Self.releases[$0]!.prerelease }!
                body = Self.json(tag)
            } else if path == prefix {
                body = "[" + ShotcutBetaChannelTests.list.map(Self.json).joined(separator: ",") + "]"
            } else if path.hasPrefix(prefix + "/tags/"),
                      case let tag = String(path.dropFirst((prefix + "/tags/").count)),
                      Self.releases[tag] != nil {
                body = Self.json(tag)
            } else {
                status = 404
                body = #"{"message":"Not Found"}"#
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func offer(to version: String, list: [String]) async throws -> RemoteVersion {
        Self.list = list
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        let source = GitHubReleasesSource(
            rules: GitHubReleaseRegistry.rules.filter { $0.bundleID == Self.id },
            session: URLSession(configuration: config))
        let app = InstalledApp(
            name: "Shotcut", bundleID: Self.id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Shotcut.app"),
            isMASApp: false, sparkleFeedURL: nil)
        return try #require(try await source.latestVersion(for: app))
    }

    @Test func aPrereleaseCopyIsOfferedTheNextPrerelease() async throws {
        let remote = try await offer(to: "26.10.30", list: ["v26.11.6", "v26.10.30", "v26.9.27"])
        #expect(remote.releaseChannel == .beta)
        #expect(remote.shortVersion == "26.11.6")
        #expect(remote.downloadURL?.lastPathComponent == "shotcut-macos-26.11.6.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
    }

    /// The stable release after a prerelease is numbered above it, and a
    /// prerelease copy is offered it.
    @Test func aPrereleaseCopyIsOfferedTheStableThatFollows() async throws {
        let remote = try await offer(
            to: "26.11.6", list: ["v26.11.20", "v26.11.6", "v26.10.30", "v26.9.27"])
        #expect(remote.shortVersion == "26.11.20")
    }

    /// Mutation: drop the beta rule → this copy reads stable and sees 26.9.28.
    @Test func withNoNewerReleaseThePrereleaseCopyIsUpToDate() async throws {
        let remote = try await offer(to: "26.10.30", list: ["v26.10.30", "v26.9.27"])
        #expect(remote.releaseChannel == .beta)
        #expect(remote.shortVersion == "26.10.30")
    }

    /// A stable copy never sees a prerelease.
    @Test func aStableCopyStaysOnStable() async throws {
        let remote = try await offer(to: "26.9.27", list: ["v26.11.6", "v26.10.30", "v26.9.27"])
        #expect(remote.releaseChannel == .stable)
        #expect(remote.shortVersion == "26.9.28")
    }

    /// The respin's version names no tag: unprovable, so stable.
    @Test func theRespinCannotBeProvenAndAnswersOnStable() async throws {
        let remote = try await offer(to: "26.9.28", list: ["v26.11.6", "v26.10.30", "v26.9.27"])
        #expect(remote.releaseChannel == .stable)
        #expect(remote.shortVersion == "26.9.28")
    }

    @Test func theBetaRuleIsProven() {
        #expect(ChannelProofRegistry.githubProofs[ChannelProofKey(Self.id, .beta)] != nil)
    }
}
