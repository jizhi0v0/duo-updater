import Testing
import Foundation
@testable import DuoUpdaterCore

// Manifest bodies below are the real `*-mac.yml` files those vendors served on
// 2026-08-31, trimmed only of entries that repeat. The arch cases are the whole
// reason this type exists, so they are tested against the exact filenames that
// caught the bug rather than against invented ones.

@Test func picksTheArm64ArtifactOverTheOneTheManifestCallsPrimary() {
    // ChatWise 26.8.0. Its top-level `path` names the **x64** build, so a reader
    // that trusted `path` would hand an Apple-silicon Mac an Intel zip — the
    // "installs fine, won't open" failure the registry pins arm64 to avoid.
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
    // Canva 1.124.1 — and note the shape that makes "first url wins" wrong: the
    // same dmg is listed three times after the zip.
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
    // Notion's default manifest. Nothing in the filename says which architecture
    // it is — which is exactly why the SOURCE probes for an `arm64-mac.yml`
    // sibling before trusting this. At the manifest level, an unmarked name is
    // taken as runnable, because most vendors ship one universal artifact and
    // label it nothing at all.
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
    // Detection without an install is an honest row; an install button that
    // fetches a build this Mac cannot run is not.
    let manifest = ElectronManifest.parse("""
        version: 3.0.0
        path: App-3.0.0-x64.zip
        sha512: SHA==
        """)
    #expect(manifest?.version == "3.0.0")
    #expect(manifest?.artifact(forArch: "arm64") == nil)
}

@Test func theTopLevelScalarsAreNotConfusedByTheNestedOnes() {
    // `url:` and `sha512:` appear at both levels meaning different things, and
    // `path`/`sha512` at the top must keep naming the primary artifact.
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
    // Same rule Sparkle applies to an enclosure, and for the same reason: the
    // manifest lists a bare filename.
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

@Test func theArchSiblingIsProbedOnlyBesideTheDefaultManifest() {
    // Only `latest-mac.yml` is asking "which architecture?".
    #expect(ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://desktop-release.notion-static.com/latest-mac.yml")!))
    // Typeless ships `channel: arm64` — already answered; probing would refetch
    // the same file.
    #expect(!ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml")!))
    // And a named CHANNEL is not asking it at all. Probing `arm64-mac.yml` beside
    // `beta-mac.yml` would move a beta user onto the stable build whenever the
    // two agreed on a version — crossing trains, not architectures.
    #expect(!ElectronManifestSource.mayProbeArchSibling(
        URL(string: "https://updates.signal.org/desktop/beta-mac.yml")!))
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
    // electron-builder normally writes LF, but a build on a Windows CI does not.
    // Splitting on "\n" alone left the WHOLE document as one line, and the damage
    // was asymmetric: the config merely came back with a nil url and failed closed,
    // while the manifest came back with `version` holding the entire file — a
    // string that then goes into a version comparison against the installed build,
    // which is how a phantom update gets invented instead of nothing happening.
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

// MARK: - #194: arch-sibling failure closure, end to end through the source
//
// These exercise `ElectronManifestSource.latestVersion(for:)` against a fake
// network so the sibling-probe *outcome* (confirmed 404 vs. anything else)
// drives whether the top-level `path` fallback is trusted, and #195's
// `RecipeHealth` wiring — not just `ElectronManifest.artifact(forArch:)` in
// isolation, which is the layer `anUnmarkedArtifactIsAccepted` already covers
// and which this file must not change the meaning of.

@Suite(.serialized)
struct ElectronArchSiblingClosureTests {

    /// Routes a fake `URLSession` by exact URL. `.serialized` on the suite (and
    /// a fresh route table per test) keeps this safe without a lock — no two
    /// tests' requests are ever in flight at once.
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        struct Response {
            let status: Int
            let body: String?
            /// Simulates a transport failure (e.g. a timeout) rather than any
            /// HTTP status at all.
            let transportFailure: Bool
        }
        // `.serialized` on the suite is the actual synchronization — no two
        // tests' requests are ever in flight together — so this is safe despite
        // not being actor-isolated.
        nonisolated(unsafe) static var routes: [String: Response] = [:]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
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

    private func electronApp(bundleID: String, domain: String) -> InstalledApp {
        InstalledApp(
            name: bundleID, bundleID: bundleID, shortVersion: "0.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil,
            electronUpdate: ElectronUpdateConfig(
                provider: "generic", url: domain, owner: nil, repo: nil, channel: "latest"))
    }

    @Test func confirmedAbsentSiblingTrustsThePathFallback() async throws {
        // Notion's shape (2026-09-01): a default manifest with no arch token in
        // its filename, and NO split published — the sibling really is a 404.
        // That is the one outcome that actually proves it, so `path` should win.
        let domain = "https://cdn-confirmed.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 7.31.3
                files:
                  - url: App-7.31.3.zip
                    sha512: ZIPSHA==
                    size: 100
                path: App-7.31.3.zip
                sha512: ZIPSHA==
                releaseDate: '2026-08-27T01:59:39.485Z'
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 404, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.confirmedAbsent"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "7.31.3")
        #expect(remote.downloadURL == URL(string: "\(domain)/App-7.31.3.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ZIPSHA==")

        let entry = await RecipeHealth.shared.snapshot().first { $0.id == bundleID }
        #expect(entry?.isHealthy == true)
    }

    @Test func forbiddenSiblingWithholdsTheArtifact() async throws {
        // Canva's shape (2026-09-01): the sibling exists but answers 403, not
        // 404. That must NOT be read as "no split" — the version is still
        // reported, but the install fields all withhold together.
        let domain = "https://cdn-403.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 2.0.0
                files:
                  - url: App-2.0.0.zip
                    sha512: ZIPSHA==
                    size: 100
                path: App-2.0.0.zip
                sha512: ZIPSHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 403, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.forbiddenSibling"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "2.0.0")
        #expect(remote.downloadURL == nil)
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA512 == nil)

        // The version itself was still real, so this is a success, not a miss.
        let entry = await RecipeHealth.shared.snapshot().first { $0.id == bundleID }
        #expect(entry?.isHealthy == true)
    }

    @Test func timedOutSiblingWithholdsTheArtifact() async throws {
        // Same shape as the 403 case, but the sibling never answers at all —
        // the other half of "403 / 超时" from the issue. A transport failure is
        // exactly as inconclusive as a non-404 status.
        let domain = "https://cdn-timeout.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 4.0.0
                files:
                  - url: App-4.0.0.zip
                    sha512: ZIPSHA==
                    size: 100
                path: App-4.0.0.zip
                sha512: ZIPSHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 0, body: nil, transportFailure: true),
        ]
        let bundleID = "com.duoupdater.test.electron.timedOutSibling"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "4.0.0")
        #expect(remote.downloadURL == nil)
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA512 == nil)
    }

    @Test func versionMismatchedSiblingWithholdsTheArtifact() async throws {
        // The sibling answers 200 but names a different release — a train
        // change, not an architecture split. Not proof of absence either.
        let domain = "https://cdn-mismatch.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 3.0.0
                files:
                  - url: App-3.0.0.zip
                    sha512: ZIPSHA==
                    size: 100
                path: App-3.0.0.zip
                sha512: ZIPSHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 200, body: """
                version: 3.0.1
                files:
                  - url: App-3.0.1-arm64.zip
                    sha512: ARMSHA==
                    size: 90
                path: App-3.0.1-arm64.zip
                sha512: ARMSHA==
                """, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.versionMismatch"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "3.0.0")
        #expect(remote.downloadURL == nil)
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA512 == nil)
    }

    @Test func aNativeArm64FilesEntryIsUnaffectedBySiblingProbeOutcome() async throws {
        // ChatWise 26.8.0's shape (2026-09-01): `files:` already carries a
        // native arm64 entry, and the top-level `path` names x64. This has
        // nothing to do with the sibling probe — `artifact(forArch:)` picks the
        // native entry before ever reaching the `path` fallback branch — so an
        // inconclusive sibling (403 here) must not change the answer.
        let domain = "https://cdn-chatwise.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
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
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 403, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.nativeArm64Entry"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "26.8.0")
        #expect(remote.downloadURL == URL(string: "\(domain)/ChatWise-26.8.0-arm64.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ARM64SHA==")
    }

    // MARK: - #195: RecipeHealth on the two ways the manifest fetch itself fails

    @Test func aNon200ManifestRecordsAMiss() async throws {
        let domain = "https://cdn-404.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 404, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.manifest404"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try await source.latestVersion(for: app)
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail == "manifest returned HTTP 404")
    }

    @Test func anUnparseableManifestBodyRecordsAMiss() async throws {
        let domain = "https://cdn-garbage.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(
                status: 200, body: "not a manifest at all", transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.manifestGarbage"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try await source.latestVersion(for: app)
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail == "manifest fetched but did not parse")
    }
}
