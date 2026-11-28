import Foundation
import Testing
@testable import DuoUpdaterCore

struct FixedNameGitHubPackageTests {
    private class Releases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        class func rows(gray: Bool, list: Bool) -> [(tag: String, prerelease: Bool, file: String)] {
            [(gray ? "0.17.0" : (list ? "v1.7.74" : "v1.22.0"), list, gray ? "Gray.zip" : "ParetoSecurity.dmg")]
        }

        override func startLoading() {
            let url = request.url!
            let gray = url.path.contains("/zenangst/Gray/")
            let list = url.lastPathComponent != "latest"
            let slug = gray ? "zenangst/Gray" : "ParetoSecurity/pareto-mac"
            let releases = Self.rows(gray: gray, list: list).map { tag, prerelease, file in
                """
                {"tag_name":"\(tag)","prerelease":\(prerelease),"draft":false,"published_at":"2026-11-25T13:00:00Z",
                 "body":"- Changes for \(tag)","assets":[
                  {"name":"\(file)","browser_download_url":"https://github.com/\(slug)/releases/download/\(tag)/\(file)"}
                ]}
                """
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((list ? "[\(releases.joined(separator: ","))]" : releases[0]).utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class CurrentParetoReleases: Releases, @unchecked Sendable {
        override class func rows(gray: Bool, list: Bool) -> [(tag: String, prerelease: Bool, file: String)] {
            // The forward prerelease has no Mac DMG. Walking back must preserve
            // the old updater's prerelease filter even past a higher stable.
            [("1.50.0", false, "ParetoSecurity.dmg"), ("1.50.1", true, "checks.json"),
             ("1.49.1", true, "ParetoSecurity.dmg")]
        }
    }

    private final class ParetoBackport: Releases, @unchecked Sendable {
        override class func rows(gray: Bool, list: Bool) -> [(tag: String, prerelease: Bool, file: String)] {
            let backport = ("1.48.2", false, "ParetoSecurity.dmg")
            return list ? [backport, ("1.51.0", true, "ParetoSecurity.dmg"),
                           ("1.50.0", false, "ParetoSecurity.dmg")] : [backport]
        }
    }

    @Test func paretoStableRanksTheSameListAsItsUpdater() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ParetoBackport.self]
        let source = GitHubReleasesSource(
            rules: niteo_co_Pareto.set.githubRules, token: "fixture", session: URLSession(configuration: config))
        let app = InstalledApp(
            name: "Pareto Security", bundleID: niteo_co_Pareto.bundleID, shortVersion: "1.49.0",
            buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Pareto Security.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
        let offer = try #require(try await source.latestVersion(for: app))
        #expect(offer.shortVersion == "1.50.0")
        #expect(offer.downloadURL?.path.hasSuffix("/1.50.0/ParetoSecurity.dmg") == true)
        #expect(offer.structuredChangelog?.entries.first?.version == "1.50.0")
        #expect(offer.releaseHistory.map(\.version) == ["1.50.0", "1.48.2"])
    }

    @Test(arguments: [
        ("com.zenangst.Gray", ReleaseChannel.stable, "0.17.0", "0.16.0"),
        ("niteo.co.Pareto", .stable, "v1.22.0", "1.21.0"),
        ("niteo.co.Pareto", .beta, "v1.7.74", "1.7.73"),
    ])
    func sameIDPackageMustCarryTheSelectedTag(
        example: (id: String, channel: ReleaseChannel, offered: String, older: String)
    ) async throws {
        let dir = try DigestOnlyInstallTests.scratch("fixed-name-release")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == example.id }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Releases.self]
        let source = GitHubReleasesSource(
            rules: rules, token: "fixture", session: URLSession(configuration: config))
        let installed = InstalledApp(
            name: "App", bundleID: example.id, shortVersion: example.older, buildVersion: "1",
            path: dir.appendingPathComponent("App.app"), isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: example.channel)
        let remote = try #require(try await source.latestVersion(for: installed))
        #expect(remote.shortVersion == example.offered)
        #expect(remote.releaseChannel == example.channel)
        for version in [example.older, example.offered] {
            let app = try await DigestOnlyInstallTests.makeApp(
                at: dir.appendingPathComponent("\(version)/App.app"), bundleID: example.id,
                version: version, build: "1", signing: .sealed(identifier: nil))
            if version == example.offered {
                try VendorInstaller.verifyOfferedPackageVersion(app: app, remote: remote, expectedBundleID: example.id)
            } else {
                do {
                    try VendorInstaller.verifyOfferedPackageVersion(app: app, remote: remote, expectedBundleID: example.id)
                    Issue.record("Accepted a sealed, same-ID package carrying the previous version")
                } catch VendorInstaller.InstallError.packageVersionMismatch(let expected, let downloaded) {
                    #expect(expected.marketing == example.offered)
                    #expect(downloaded.marketing == example.older)
                }
            }
        }
    }

    @Test(arguments: [
        ("0.0.19", "1.50.0"), ("0.0.21", "1.50.0"), ("0.0.22", "1.49.1"),
        ("v1.7.74", "1.49.1"), ("1.21.1", "1.49.1"), ("1.21.2", "1.50.0"), ("1.49.1", "1.50.0"),
    ])
    func paretoBetaFollowsTheInstalledUpdatersReleasePolicy(example: (installed: String, target: String)) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CurrentParetoReleases.self]
        let source = GitHubReleasesSource(
            rules: niteo_co_Pareto.set.githubRules, token: "fixture", session: URLSession(configuration: config))
        let app = InstalledApp(
            name: "Pareto Security", bundleID: niteo_co_Pareto.bundleID, shortVersion: example.installed,
            buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Pareto Security.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .beta)
        let offer = try #require(try await source.latestVersion(for: app))
        #expect(offer.shortVersion == example.target)
        #expect(offer.downloadURL?.path.hasSuffix("/\(example.target)/ParetoSecurity.dmg") == true)
        #expect(offer.structuredChangelog?.entries.first?.version == example.target)
        #expect(offer.releaseHistory.map(\.version).contains("1.50.0") == (example.target == "1.50.0"))
        #expect(!offer.releaseHistory.contains { $0.version == "1.50.1" })
    }

    @Test func paretoMatchesOnlyWholeReleaseTags() {
        for rule in niteo_co_Pareto.set.githubRules {
            for tag in ["1.50.0", "v1.22.0", "v1.7.74"] {
                #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
                    == tag)
            }
            for tag in ["foo-v1.22.0", "vv1.22.0", "v1.22.0-rc1", "v1.22.0\n"] {
                #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern) == nil)
            }
        }
    }
}
