import Foundation
import Testing
@testable import DuoUpdaterCore

private let migrationFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/ElectronBlockmap")

struct ElectronZIPMigrationTests {
    struct GitHubCase: Decodable {
        let bundleID: String
        let channel: String
        let tag: String
        let expectedZIP: String
        let assets: [String]
    }
    struct VendorCase: Decodable, Sendable {
        let bundleID: String
        let channel: String
        let fixture: String
        let feedURL: String
        let version: String
        let expectedZIP: String
        let expectedSHA512: String
    }

    @Test func everyMigratedGitHubRuleSelectsItsVerifiedMacZIP() throws {
        let cases = try JSONDecoder().decode([GitHubCase].self,
            from: Data(contentsOf: migrationFixtures.appendingPathComponent("github-migrations.json")))
        #expect(!cases.isEmpty)
        for item in cases {
            let channel = try #require(ReleaseChannel(rawValue: item.channel))
            let rule = try #require(GitHubReleaseRegistry.rules.first {
                $0.bundleID == item.bundleID && $0.channel == channel
            })
            let pattern = try #require(rule.installAssetPattern)
            #expect(rule.installerKind == .zip, "\(item.bundleID) [\(channel)]")
            let assets = item.assets.map {
                (name: $0, url: URL(string: "https://example.com/")!.appendingPathComponent($0), size: Int64?.none)
            }
            let selected = GitHubReleaseRule.installableAsset(from: assets, matching: pattern,
                                                              preferring: .arm64, allowingIntelTranslation: true)
            #expect(selected?.url.lastPathComponent == item.expectedZIP, "\(item.bundleID) [\(channel)]")
            for excluded in item.assets where excluded.hasSuffix(".dmg") || excluded.hasSuffix(".blockmap") {
                #expect(excluded.range(of: pattern, options: .regularExpression) == nil)
            }
        }
    }

    @Test func vendorResolverBindsEachZIPToItsOwnPublishedHash() async throws {
        let cases = try JSONDecoder().decode([VendorCase].self,
            from: Data(contentsOf: migrationFixtures.appendingPathComponent("vendor-migrations.json")))
        #expect(!cases.isEmpty)
        for item in cases {
            let channel = try #require(ReleaseChannel(rawValue: item.channel))
            let recipe = try #require(VendorProbeRegistry.recipes.first {
                $0.bundleID == item.bundleID && $0.channel == channel
            })
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MigrationFeedStub.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let source = VendorProbeSource(recipes: [recipe], session: session)
            let app = InstalledApp(name: item.bundleID, bundleID: item.bundleID, shortVersion: "0.0.1",
                buildVersion: "0.0.1", path: URL(fileURLWithPath: "/Applications/MigrationFixture.app"),
                isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
            let remote = try #require(try await source.latestVersion(for: app))
            #expect(remote.shortVersion == item.version)
            #expect(remote.vendorInstallerKind == .zip)
            #expect(remote.downloadURL?.lastPathComponent == item.expectedZIP)
            #expect(remote.expectedSHA512 == item.expectedSHA512)
            #expect(Data(base64Encoded: item.expectedSHA512)?.count == 64)
        }
    }

    private final class MigrationFeedStub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let cases = try JSONDecoder().decode([VendorCase].self,
                    from: Data(contentsOf: migrationFixtures.appendingPathComponent("vendor-migrations.json")))
                guard let item = cases.first(where: { $0.feedURL == request.url?.absoluteString }) else {
                    throw URLError(.unsupportedURL)
                }
                let body = try Data(contentsOf: migrationFixtures.appendingPathComponent(item.fixture))
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                                headerFields: ["Content-Type": "text/yaml"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() {}
    }
}
