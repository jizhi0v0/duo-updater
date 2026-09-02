import Testing
import Foundation
@testable import DuoUpdaterCore

// Manifest bodies below are the real `*-mac.yml` shapes those vendors served.
// The architecture cases use the exact filenames that caught the original bug.

@Test func picksTheArm64ArtifactOverTheOneTheManifestCallsPrimary() {
    // ChatWise 26.8.0. Its top-level `path` names the **x64** build.
    let manifest = ElectronManifest.parse("""
        version: 26.8.0
        files:
          - url: ChatWise-26.8.0-x64.zip
            sha512: X64SHA==
            size: 100
          - url: ChatWise-26.8.0-arm64.zip
            sha512: ARM64SHA==
            size: 99
        path: ChatWise-26.8.0-x64.zip
        sha512: X64SHA==
        releaseDate: '2026-08-27T01:59:39.485Z'
        """)
    let file = try! #require(manifest?.artifact(forArch: "arm64"))
    #expect(file.url == "ChatWise-26.8.0-arm64.zip")
    #expect(file.sha512 == "ARM64SHA==")
}

@Test func fallsBackToTheUniversalArtifactWhenNoArchIsNamed() {
    let manifest = ElectronManifest.parse("""
        version: 1.124.1
        files:
          - url: Canva-1.124.1-universal-mac.zip
            sha512: ZIPSHA==
            size: 220714081
          - url: Canva-1.124.1-universal.dmg
            sha512: DMGSHA==
            size: 229488791
          - url: Canva-1.124.1-universal.dmg
            sha512: DMGSHA==
            size: 229488791
        path: Canva-1.124.1-universal-mac.zip
        sha512: ZIPSHA==
        """)
    #expect(manifest?.artifact()?.url == "Canva-1.124.1-universal-mac.zip")
}

@Test func anUnmarkedArtifactIsAccepted() {
    // An unmarked name is potentially universal; Gate 5/5b verifies the staged
    // app's executable architecture before it can replace the current bundle.
    let manifest = ElectronManifest.parse("""
        version: 7.31.3
        files:
          - url: Notion-7.31.3.zip
            sha512: ZIPSHA==
            size: 126113061
        path: Notion-7.31.3.zip
        sha512: ZIPSHA==
        """)
    #expect(manifest?.artifact()?.url == "Notion-7.31.3.zip")
}

@Test func anX64OnlyManifestOffersNoArtifactAtAll() {
    let manifest = ElectronManifest.parse("""
        version: 3.0.0
        path: App-3.0.0-x64.zip
        sha512: SHA==
        """)
    #expect(manifest?.version == "3.0.0")
    #expect(manifest?.artifact(forArch: "arm64") == nil)
}

@Test func theTopLevelScalarsAreNotConfusedByTheNestedOnes() {
    let manifest = try! #require(ElectronManifest.parse("""
        version: 7.31.3
        files:
          - url: Notion-7.31.3.zip
            sha512: FILESHA==
            size: 126113061
        path: Notion-7.31.3.zip
        sha512: TOPSHA==
        releaseDate: '2026-08-27T01:59:39.485Z'
        """))
    #expect(manifest.version == "7.31.3")
    #expect(manifest.sha512 == "TOPSHA==")
    #expect(manifest.files.count == 1)
    #expect(manifest.files[0].sha512 == "FILESHA==")
    #expect(manifest.releaseDate == "2026-08-27T01:59:39.485Z")
}

@Test func aBodyWithNoVersionIsNotAManifest() {
    #expect(ElectronManifest.parse("files:\n  - url: x.zip\n") == nil)
    #expect(ElectronManifest.parse("") == nil)
}

@Test func artifactURLsResolveAgainstTheManifestsOwnDirectory() {
    let manifest = ElectronManifest.parse("""
        version: 2.4.0
        path: Typeless-2.4.0-arm64.zip
        sha512: SHA==
        """)
    let url = manifest?.artifactURL(
        relativeTo: URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!)
    #expect(url == URL(string: "https://typeless-static.com/desktop-release/Typeless-2.4.0-arm64.zip"))
}

// MARK: - the source's own rules

@Test func eachDeclaredChannelResolvesToItsOwnManifest() {
    func manifest(_ channel: String) -> URL? {
        ElectronUpdateConfig(
            provider: "generic", url: "https://example.invalid/releases",
            owner: nil, repo: nil, channel: channel).manifestURL
    }
    #expect(manifest("latest") == URL(string: "https://example.invalid/releases/latest-mac.yml"))
    #expect(manifest("arm64") == URL(string: "https://example.invalid/releases/arm64-mac.yml"))
    #expect(manifest("beta") == URL(string: "https://example.invalid/releases/beta-mac.yml"))
}

@Test func theInstallerKindComesFromTheChosenArtifact() {
    #expect(ElectronManifestSource.kind(of: "Notion-arm64-7.31.3.zip") == .zip)
    #expect(ElectronManifestSource.kind(of: "Canva-1.124.1-universal.dmg") == .dmg)
    #expect(ElectronManifestSource.kind(of: nil) == nil)
    #expect(ElectronManifestSource.kind(of: "manifest.yml") == nil)
}

@Test func anAppWithNoElectronConfigIsNotThisSourcesBusiness() async throws {
    let app = InstalledApp(
        name: "Nothing", bundleID: "com.example.nothing", shortVersion: "1.0",
        buildVersion: "1", path: URL(fileURLWithPath: "/Applications/Nothing.app"),
        isMASApp: false, sparkleFeedURL: nil)
    #expect(try await ElectronManifestSource().latestVersion(for: app) == nil)
}

@Test func aCRLFManifestIsReadLineWiseLikeAnyOther() {
    let cfg = ElectronUpdateConfig.parse(
        "provider: generic\r\nurl: https://example.invalid\r\nchannel: latest\r\n")
    #expect(cfg?.url == "https://example.invalid")
    #expect(cfg?.manifestURL == URL(string: "https://example.invalid/latest-mac.yml"))

    let manifest = ElectronManifest.parse(
        "version: 1.2.3\r\nfiles:\r\n  - url: A-1.2.3-arm64.zip\r\n"
        + "    sha512: S==\r\npath: A-1.2.3-arm64.zip\r\n")
    #expect(manifest?.version == "1.2.3")
    #expect(manifest?.files.count == 1)
    #expect(manifest?.artifact()?.url == "A-1.2.3-arm64.zip")
    #expect(manifest?.artifact()?.sha512 == "S==")
}

// MARK: - source integration and health

@Suite(.serialized)
struct ElectronManifestSourceTests {
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        struct Response {
            let status: Int
            let body: String?
            let transportFailure: Bool
        }

        nonisolated(unsafe) static var routes: [String: Response] = [:]
        nonisolated(unsafe) static var requestedURLs: [String] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            Self.requestedURLs.append(url.absoluteString)
            guard let route = Self.routes[url.absoluteString] else {
                let response = HTTPURLResponse(
                    url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if route.transportFailure {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            let response = HTTPURLResponse(
                url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let body = route.body {
                client?.urlProtocol(self, didLoad: body.data(using: .utf8)!)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func electronApp(
        bundleID: String, domain: String, channel: String = "latest"
    ) -> InstalledApp {
        InstalledApp(
            name: bundleID, bundleID: bundleID, shortVersion: "0.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil,
            electronUpdate: ElectronUpdateConfig(
                provider: "generic", url: domain, owner: nil, repo: nil, channel: channel))
    }

    @Test func theBundleDeclaredManifestIsTheOnlyTrackRead() async throws {
        // Current Notion-shaped pair (2026-09-02). Both manifests can publish the
        // same version, but `channel: latest` reads only `latest-mac.yml`.
        let domain = "https://desktop-release.notion-static.com"
        FixtureProtocol.requestedURLs = []
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 7.32.0
                files:
                  - url: Notion-7.32.0.zip
                    sha512: LATESTSHA==
                    size: 127948435
                path: Notion-7.32.0.zip
                sha512: LATESTSHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 200, body: """
                version: 7.32.0
                files:
                  - url: Notion-arm64-7.32.0.zip
                    sha512: ARMSHA==
                    size: 122788925
                path: Notion-arm64-7.32.0.zip
                sha512: ARMSHA==
                """, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.declaredTrack"
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(
            for: electronApp(bundleID: bundleID, domain: domain)))
        #expect(remote.shortVersion == "7.32.0")
        #expect(remote.downloadURL == URL(string: "\(domain)/Notion-7.32.0.zip"))
        #expect(remote.expectedSHA512 == "LATESTSHA==")
        #expect(FixtureProtocol.requestedURLs == ["\(domain)/latest-mac.yml"])

        let entry = await RecipeHealth.shared.snapshot().first { $0.id == bundleID }
        #expect(entry?.isHealthy == true)
    }

    @Test func aNon200ManifestRecordsAMiss() async throws {
        let domain = "https://cdn-404.example.test"
        FixtureProtocol.requestedURLs = []
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 404, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.manifest404"
        let remote = try await ElectronManifestSource(session: fixtureSession()).latestVersion(
            for: electronApp(bundleID: bundleID, domain: domain))
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail == "manifest returned HTTP 404")
    }

    @Test func anUnparseableManifestBodyRecordsAMiss() async throws {
        let domain = "https://cdn-garbage.example.test"
        FixtureProtocol.requestedURLs = []
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(
                status: 200, body: "not a manifest at all", transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.manifestGarbage"
        let remote = try await ElectronManifestSource(session: fixtureSession()).latestVersion(
            for: electronApp(bundleID: bundleID, domain: domain))
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail == "manifest fetched but did not parse")
    }

    @Test func aTransportFailureOnTheManifestFetchDegradesInsteadOfThrowing() async throws {
        let domain = "https://cdn-transport-failure.example.test"
        FixtureProtocol.requestedURLs = []
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 0, body: nil, transportFailure: true),
        ]
        let bundleID = "com.duoupdater.test.electron.manifestTransportFailure"
        let remote = try await ElectronManifestSource(session: fixtureSession()).latestVersion(
            for: electronApp(bundleID: bundleID, domain: domain))
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail?.hasPrefix("manifest fetch failed:") == true)
    }

    @Test func aFilesEntryMissingItsChecksumWithholdsAllThreeFields() async throws {
        let domain = "https://cdn-missing-checksum.example.test"
        FixtureProtocol.requestedURLs = []
        FixtureProtocol.routes = [
            "\(domain)/arm64-mac.yml": .init(status: 200, body: """
                version: 6.0.0
                files:
                  - url: App-6.0.0-arm64.zip
                path: App-6.0.0-arm64.zip
                sha512: TOPSHA==
                """, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.missingChecksum"
        let remote = try #require(await ElectronManifestSource(
            session: fixtureSession()).latestVersion(
                for: electronApp(bundleID: bundleID, domain: domain, channel: "arm64")))
        #expect(remote.shortVersion == "6.0.0")
        #expect(remote.downloadURL == nil)
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA512 == nil)

        let entry = await RecipeHealth.shared.snapshot().first { $0.id == bundleID }
        #expect(entry?.isHealthy == true)
    }
}
