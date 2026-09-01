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
        /// For the retry test: a URL that must answer differently across
        /// successive requests (a 502 then a 200), which a single `Response`
        /// per URL can't express. Consulted before `routes`; the last entry
        /// repeats once the sequence is exhausted.
        nonisolated(unsafe) static var sequenceRoutes: [String: [Response]] = [:]
        nonisolated(unsafe) static var sequenceCallCount: [String: Int] = [:]

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            let route: Response
            if let sequence = Self.sequenceRoutes[url.absoluteString], !sequence.isEmpty {
                let call = Self.sequenceCallCount[url.absoluteString, default: 0]
                Self.sequenceCallCount[url.absoluteString] = call + 1
                route = sequence[min(call, sequence.count - 1)]
            } else if let fixed = Self.routes[url.absoluteString] {
                route = fixed
            } else {
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
        // A CONSTRUCTED fixture, not Canva's — flagged in PR #201 review because
        // an earlier version of this comment claimed it was. Canva's sibling
        // really does answer 403 (2026-09-01, both #194 and #203 observed it
        // directly), but Canva's DEFAULT manifest names a `universal` artifact
        // (`fallsBackToTheUniversalArtifactWhenNoArchIsNamed` above, real body),
        // which wins in `artifact(forArch:)`'s universal branch — BEFORE the
        // top-level `path` fallback branch this withholding logic guards. So
        // Canva's real 403 never reaches the code path this test exercises; see
        // `aRealCanvaShapedManifestIsUnaffectedByItsForbiddenSibling` below for
        // Canva's actual (unaffected) behavior, verified against its real body.
        // This fixture exists because the combination this test DOES need to
        // cover — an unmarked top-level-`path` artifact plus a non-404 sibling —
        // has no known live example as of 2026-09-01; it is exercised here as a
        // synthetic case, the same way `anX64OnlyManifestOffersNoArtifactAtAll`
        // synthesizes a manifest shape rather than pointing at a real vendor.
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

    @Test func aRealCanvaShapedManifestIsUnaffectedByItsForbiddenSibling() async throws {
        // Canva's ACTUAL shape, end to end (2026-09-01, real bodies): its default
        // manifest names a `universal` artifact, which `artifact(forArch:)` picks
        // before ever considering the top-level `path` fallback branch — so the
        // sibling probe's outcome (a real 403 here) is irrelevant to whether an
        // artifact is offered. This is the test the comment on
        // `forbiddenSiblingWithholdsTheArtifact` used to (wrongly) claim that one
        // covered.
        let domain = "https://desktop-release.canva.com"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 1.124.1
                files:
                  - url: Canva-1.124.1-universal-mac.zip
                    sha512: ZIPSHA==
                    size: 220714081
                  - url: Canva-1.124.1-universal.dmg
                    sha512: DMGSHA==
                    size: 229488791
                path: Canva-1.124.1-universal-mac.zip
                sha512: ZIPSHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 403, body: nil, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.canvaReal"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "1.124.1")
        #expect(remote.downloadURL == URL(string: "\(domain)/Canva-1.124.1-universal-mac.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ZIPSHA==")
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

    // MARK: - #203: a resolved sibling is adopted wholesale, version and all

    @Test func aHigherVersionedSiblingIsAdoptedWholesale() async throws {
        // The real Notion shape, 2026-09-01: the two tracks had drifted four
        // days apart. `latest-mac.yml` (x64) still said 7.31.3; `arm64-mac.yml`
        // had shipped 7.32.0 on 2026-08-31. The OLD equality guard made this
        // source report 7.31.3 — the installed version — so an arm64 host was
        // told "already up to date" while four days behind. It must now report
        // 7.32.0 and the arm64 artifact.
        let domain = "https://cdn-higher.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 7.31.3
                files:
                  - url: Notion-7.31.3.zip
                    sha512: X64SHA==
                    size: 126113061
                path: Notion-7.31.3.zip
                sha512: X64SHA==
                releaseDate: '2026-08-27T01:59:39.485Z'
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 200, body: """
                version: 7.32.0
                files:
                  - url: Notion-arm64-7.32.0.zip
                    sha512: ARMSHA==
                    size: 121001845
                path: Notion-arm64-7.32.0.zip
                sha512: ARMSHA==
                releaseDate: '2026-08-31T20:30:08.402Z'
                """, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.higherSibling"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "7.32.0")
        #expect(remote.downloadURL == URL(string: "\(domain)/Notion-arm64-7.32.0.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ARMSHA==")
    }

    @Test func aLowerVersionedSiblingIsAlsoAdoptedWholesale() async throws {
        // The mirror case named explicitly in #203: the arm64 track can just as
        // easily be BEHIND the default manifest, and that is still the real
        // state of the arm64 track — reporting it is correct, not a regression
        // to an older version.
        let domain = "https://cdn-lower.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 5.1.0
                files:
                  - url: App-5.1.0.zip
                    sha512: X64SHA==
                    size: 100
                path: App-5.1.0.zip
                sha512: X64SHA==
                """, transportFailure: false),
            "\(domain)/arm64-mac.yml": .init(status: 200, body: """
                version: 5.0.9
                files:
                  - url: App-5.0.9-arm64.zip
                    sha512: ARMSHA==
                    size: 95
                path: App-5.0.9-arm64.zip
                sha512: ARMSHA==
                """, transportFailure: false),
        ]
        let bundleID = "com.duoupdater.test.electron.lowerSibling"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "5.0.9")
        #expect(remote.downloadURL == URL(string: "\(domain)/App-5.0.9-arm64.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ARMSHA==")
    }

    @Test func aTransientGatewayErrorOnTheSiblingIsRetriedRatherThanTreatedAsIndeterminate() async throws {
        // #203's second finding: the default manifest fetch retries a gateway
        // 502/503/504 once (`versionFeedData`), but the sibling probe used to go
        // through a bare `data(for:)` with none of that — so the identical
        // transient status self-healed on one request and got read as
        // "inconclusive, withhold the artifact" on the other. The sibling here
        // 502s once, then answers normally; that must resolve, not withhold.
        let domain = "https://cdn-gateway-retry.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 200, body: """
                version: 9.0.0
                files:
                  - url: App-9.0.0.zip
                    sha512: X64SHA==
                    size: 100
                path: App-9.0.0.zip
                sha512: X64SHA==
                """, transportFailure: false),
        ]
        FixtureProtocol.sequenceRoutes = [
            "\(domain)/arm64-mac.yml": [
                .init(status: 502, body: nil, transportFailure: false),
                .init(status: 200, body: """
                    version: 9.0.0
                    files:
                      - url: App-9.0.0-arm64.zip
                        sha512: ARMSHA==
                        size: 90
                    path: App-9.0.0-arm64.zip
                    sha512: ARMSHA==
                    """, transportFailure: false),
            ],
        ]
        let bundleID = "com.duoupdater.test.electron.gatewayRetrySibling"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "9.0.0")
        #expect(remote.downloadURL == URL(string: "\(domain)/App-9.0.0-arm64.zip"))
        #expect(remote.vendorInstallerKind == .zip)
        #expect(remote.expectedSHA512 == "ARMSHA==")
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

    @Test func aTransportFailureOnTheManifestFetchDegradesInsteadOfThrowing() async throws {
        // PR #201 review, #4: only the non-200 branch used to degrade to nil —
        // a plain transport failure (timeout, DNS, connection refused, …)
        // reaching `manifestURL` itself propagated straight out of
        // `latestVersion` as a thrown error. Since this source sits LAST in
        // `SourceStack`, that put an error row on an app whose real state might
        // just be "no coverage yet" — exactly what the non-200 branch's own
        // "degrade rather than throw" reasoning says to avoid, just not applied
        // to this failure shape. Must not throw, and must record a miss like
        // every other way this source fails to read a manifest.
        let domain = "https://cdn-transport-failure.example.test"
        FixtureProtocol.routes = [
            "\(domain)/latest-mac.yml": .init(status: 0, body: nil, transportFailure: true),
        ]
        let bundleID = "com.duoupdater.test.electron.manifestTransportFailure"
        let app = electronApp(bundleID: bundleID, domain: domain)
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try await source.latestVersion(for: app)
        #expect(remote == nil)

        let entry = try #require(await RecipeHealth.shared.snapshot().first { $0.id == bundleID })
        #expect(entry.isHealthy == false)
        #expect(entry.lastMissDetail?.hasPrefix("manifest fetch failed:") == true)
    }

    // MARK: - PR #201 review, #3: the three install fields actually move together

    @Test func aFilesEntryMissingItsChecksumWithholdsAllThreeFields() async throws {
        // The reachable half of the "three fields drift apart" bug flagged in
        // review: a `files:` entry can name a `url:` with no `sha512:` line
        // under it. Deriving `expectedSHA512` as `file?.sha512` independently of
        // `downloadURL`/`vendorInstallerKind` used to let this through as a
        // download offer with no checksum to verify it against — silently
        // skipping the integrity check `VendorInstaller` would otherwise run.
        //
        // Named channel (not `latest-mac.yml`) so no sibling probe is in play at
        // all — this withholding reason is orthogonal to #194/#203's.
        let domain = "https://cdn-missing-checksum.example.test"
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
        let app = electronApp(bundleID: bundleID, domain: domain, channel: "arm64")
        let source = ElectronManifestSource(session: fixtureSession())

        let remote = try #require(await source.latestVersion(for: app))
        #expect(remote.shortVersion == "6.0.0")
        #expect(remote.downloadURL == nil)
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA512 == nil)

        // The version was still real and cleanly parsed — this is a success,
        // not a miss, same as the sibling-withholding cases above.
        let entry = await RecipeHealth.shared.snapshot().first { $0.id == bundleID }
        #expect(entry?.isHealthy == true)
    }
}
