import Foundation
import Testing
@testable import DuoUpdaterCore

struct RuneGitHubTests {
    private final class Feed: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let url = request.url!
            let data: Data
            let statusCode: Int
            switch url.path {
            case "/repos/Losses/rune/releases/latest":
                statusCode = 200
                data = Data(Self.release(
                    "v1.1.0", fileTag: "v1.1.0", prerelease: false,
                    notes: "## New Features\\n- Introduced lyrics display functionality\\n\\n## Improvements\\n- Improved randomization algorithm").utf8)
            case "/repos/Losses/rune/releases":
                // An older release above the latest must not decide the offer.
                // An asset whose name carries an earlier version is no proof.
                statusCode = 200
                let releases = [
                    Self.release("v2.0.0-alpha.16", fileTag: "v2.0.0-alpha.16", prerelease: true,
                                 notes: "- Previous preview"),
                    Self.release("v2.0.0-alpha.18", fileTag: "v2.0.0-alpha.17", prerelease: true,
                                 notes: "- Stale installer"),
                    Self.release("v2.0.0-alpha.17", fileTag: "v2.0.0-alpha.17", prerelease: true,
                                 notes: "## Features\\n- Support Apple Music libraries\\n\\n## Improvements\\n- Update translations")
                ]
                data = Data(("[" + releases.joined(separator: ",") + "]").utf8)
            case "/Losses/rune/refs/tags/v1.1.0/pubspec.yaml":
                statusCode = 200
                data = Data("name: bandwagon\r\nversion: 1.1.4002\r\n".utf8)
            case "/Losses/rune/refs/tags/v2.0.0-alpha.17/pubspec.yaml":
                statusCode = 200
                data = Data("name: bandwagon\nversion: 2.0.1017\n".utf8)
            default:
                statusCode = 404
                data = Data()
            }
            if url.host == "raw.githubusercontent.com" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            }
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        private static func release(_ tag: String, fileTag: String, prerelease: Bool, notes: String) -> String {
            """
            {
              "tag_name": "\(tag)", "prerelease": \(prerelease), "draft": false,
              "published_at": "2026-11-28T02:50:07Z", "body": "\(notes)",
              "assets": [{
                "name": "Rune-\(fileTag)-macOS.dmg",
                "browser_download_url": "https://github.com/Losses/rune/releases/download/\(tag)/Rune-\(fileTag)-macOS.dmg"
              }]
            }
            """
        }
    }

    private func app(_ version: String) -> InstalledApp {
        let channel = ReleaseChannel.detect(
            name: "Rune", bundleID: ci_not_rune.bundleID, keystoneChannel: nil, version: version)
        return InstalledApp(
            name: "Rune", bundleID: ci_not_rune.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/Rune.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: channel)
    }

    @Test(arguments: [false, true])
    func runeUsesEachTracksRealBundleVersion(alpha: Bool) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Feed.self]
        let source = GitHubReleasesSource(
            rules: ci_not_rune.set.githubRules, token: "fixture-token", session: URLSession(configuration: configuration))
        let old = app(alpha ? "2.0.1016" : "1.0.4002")
        let newest = alpha ? "2.0.1017" : "1.1.4002"
        let tag = alpha ? "v2.0.0-alpha.17" : "v1.1.0"
        let remote = try #require(try await source.latestVersion(for: old))

        #expect(remote.releaseChannel == (alpha ? .alpha : .stable))
        #expect(remote.shortVersion == newest)
        #expect(remote.version == newest)
        #expect(remote.marketingMatchesBundle)
        #expect(remote.downloadURL?.absoluteString ==
            "https://github.com/Losses/rune/releases/download/\(tag)/Rune-\(tag)-macOS.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(UpdateChecker.evaluate(installed: old, remote: remote) == .updateAvailable(latest: newest))
        #expect(UpdateChecker.evaluate(installed: app(newest), remote: remote) == .upToDate)
        let entry = try #require(remote.structuredChangelog?.entries.first)
        #expect(entry.version == String(tag.dropFirst()))
        #expect(remote.publisherVersion == entry.version)
        let timelineEntry = try #require(remote.releaseHistory.first { $0.version == remote.publisherVersion })
        #expect(timelineEntry.publishedAt == remote.publishedAt)
        #expect(timelineEntry.vendorDay == remote.vendorDay)
        let headings = entry.content.compactMap { block -> String? in
            if case .heading(let heading) = block { return heading }
            return nil
        }
        #expect(headings == (alpha ? ["Features", "Improvements"] : ["New Features", "Improvements"]))
    }

    @Test func aSkippedAlphaInstallerIsReportedAgainstTheSelectedTag() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Feed.self]
        let source = GitHubReleasesSource(
            rules: ci_not_rune.set.githubRules, token: nil, session: URLSession(configuration: configuration))
        let alpha = try #require(ci_not_rune.set.githubRules.first { $0.channel == .alpha })
        let outcome = await source.resolveDiagnostic(alpha)
        #expect(outcome.remote?.shortVersion == "2.0.1017")
        #expect(outcome.warnings == [.installAssetRenamed(
            release: "v2.0.0-alpha.18", assets: ["Rune-v2.0.0-alpha.17-macOS.dmg"], offered: "2.0.1017")])
    }

    @Test func aVersionFromAnotherTrackOrMinorIsRefused() {
        #expect(ci_not_rune.bundleVersion(in: "version: 2.0.1017\n", release: "2.0.0", channel: .stable) == nil)
        #expect(ci_not_rune.bundleVersion(in: "version: 1.1.4002\n", release: "1.0.0", channel: .stable) == nil)
        #expect(ci_not_rune.bundleVersion(in: "version: 2.0.4002\n", release: "2.0.0-alpha.17", channel: .alpha) == nil)
        #expect(ci_not_rune.bundleVersion(in: "version: 2.0.1017+11\n", release: "2.0.0-alpha.17", channel: .alpha) == nil)
    }
}
