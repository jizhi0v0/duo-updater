import Foundation
import Testing
@testable import DuoUpdaterCore

/// UTM's bundle has no local Beta marker, and its previews are not a parallel
/// train — they graduate into the same numbering. These tests exercise the whole
/// path: prove the installed copy's channel from the exact GitHub release, then
/// pick what that copy should actually be offered.
///
/// The fixture is shaped like the real repository rather than like a two-channel
/// app, because that shape is what the code is for: `v4.7.0…v4.7.3` shipped as
/// "(Beta)" and `v4.7.4`/`v4.7.5` did not, while `v5.0.x` is a preview line that
/// has not graduated yet.
@Suite(.serialized)
struct UTMGitHubChannelTests {
    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        /// Every request path this protocol served, so a test can assert about
        /// requests NOT made — the memoised second check is invisible otherwise.
        nonisolated(unsafe) static var requested: [String] = []
        private static let lock = NSLock()
        static func record(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            requested.append(path)
        }
        static func reset() {
            lock.lock(); defer { lock.unlock() }
            requested = []
        }
        static func paths() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return requested
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let path = request.url?.path ?? ""
            Self.record(path)
            let body: String
            let status: Int
            switch path {
            case "/repos/utmapp/UTM/releases/tags/v5.0.4":
                status = 200
                body = Self.release(tag: "v5.0.4", prerelease: true, body: "* Installed Beta")
            case "/repos/utmapp/UTM/releases/tags/v4.7.3":
                status = 200
                body = Self.release(tag: "v4.7.3", prerelease: true, body: "* Installed old Beta")
            case "/repos/utmapp/UTM/releases/tags/v4.7.4":
                status = 200
                body = Self.release(tag: "v4.7.4", prerelease: false, body: "* Installed Stable")
            case "/repos/utmapp/UTM/releases/tags/v3.0.0":
                status = 200
                body = Self.release(tag: "v3.0.0", prerelease: true, body: "* Abandoned line")
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
                body = "[" + [
                    // Never offerable, at any version: a draft is not a release.
                    Self.release(tag: "v5.0.6", prerelease: true, draft: true,
                                 body: "* Unpublished draft"),
                    Self.release(tag: "v5.0.5", prerelease: true,
                                 body: "## Changes (v5.0.5)\n* Beta-only DirectX update"),
                    Self.release(tag: "v5.0.4", prerelease: true,
                                 body: "## Changes (v5.0.4)\n* Beta-only earlier preview"),
                    Self.release(tag: "v4.7.5", prerelease: false,
                                 body: "## Changes (v4.7.5)\n* Stable-only QEMU update"),
                    Self.release(tag: "v4.7.4", prerelease: false,
                                 body: "## Changes (v4.7.4)\n* Stable-only graduation"),
                    Self.release(tag: "v4.7.3", prerelease: true,
                                 body: "## Changes (v4.7.3)\n* Beta-only 4.7 preview"),
                    Self.release(tag: "v3.0.0", prerelease: true,
                                 body: "## Changes (v3.0.0)\n* Beta-only ancient preview"),
                ].joined(separator: ",") + "]"
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

        private static func release(
            tag: String, prerelease: Bool, draft: Bool = false, body: String
        ) -> String {
            let escapedBody = body
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return """
            {
              "tag_name":"\(tag)",
              "prerelease":\(prerelease),
              "draft":\(draft),
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

    private func source(channelStore: ResolvedChannelStore? = nil) -> GitHubReleasesSource {
        FixtureProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == "com.utmapp.UTM" }
        return GitHubReleasesSource(
            rules: rules, session: URLSession(configuration: configuration),
            channelStore: channelStore)
    }

    private func app(version: String) -> InstalledApp {
        InstalledApp(
            name: "UTM", bundleID: "com.utmapp.UTM",
            shortVersion: version, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/UTM.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private func tempStore() -> ResolvedChannelStore {
        ResolvedChannelStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utm-channels-\(UUID().uuidString).json"))
    }

    @Test func aPreviewInstallIsOfferedTheNewestPreviewOfItsOwnLine() async throws {
        let remote = try #require(try await source().latestVersion(for: app(version: "5.0.4")))

        #expect(remote.displayVersion == "5.0.5")
        #expect(remote.releaseChannel == .beta)
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.requiresManualInstaller == false)
        #expect(remote.downloadURL?.absoluteString
                == "https://github.com/utmapp/UTM/releases/download/v5.0.5/UTM.dmg")
        // The draft one version above it is never a candidate.
        #expect(!remote.releaseHistory.map(\.version).contains("5.0.6"))
        let items = try #require(remote.structuredChangelog?.entries.first?.items)
        #expect(items.contains { $0.contains("Beta-only DirectX update") })
    }

    /// The case both obvious answers get wrong, and the reason this rule is
    /// line-anchored rather than filtered or newest-first.
    ///
    /// A copy on `4.7.3 (Beta)` sits on a line that has since graduated. Offering
    /// it only prereleases strands it — the newest prerelease it would ever see is
    /// itself, so it reads "up to date" while `4.7.5` ships. Offering it the newest
    /// release of any kind walks it onto `5.0.5`, a preview of a line that has not
    /// shipped. The answer it wants is its own line's graduation.
    @Test func aPreviewInstallWhoseLineGraduatedIsOfferedThatGraduation() async throws {
        let remote = try #require(try await source().latestVersion(for: app(version: "4.7.3")))

        #expect(remote.displayVersion == "4.7.5")
        #expect(remote.displayVersion != "5.0.5", "a 4.7 preview must not be walked onto the v5 line")
        #expect(remote.downloadURL?.absoluteString
                == "https://github.com/utmapp/UTM/releases/download/v4.7.5/UTM.dmg")
        // Its notes have to exist, which is what `includesPromotedStable` buys:
        // the release it is being offered is not a prerelease.
        let items = try #require(remote.structuredChangelog?.entries.first?.items)
        #expect(items.contains { $0.contains("Stable-only QEMU update") })
    }

    /// The other half of the ceiling: a line nobody ships any more must not pin
    /// the install to it forever.
    @Test func aPreviewInstallOnAnAbandonedLineFallsForwardToTheNewestStable() async throws {
        let remote = try #require(try await source().latestVersion(for: app(version: "3.0.0")))
        #expect(remote.displayVersion == "4.7.5")
    }

    @Test func aStableInstallStaysOnTheStableTrackAndNeverSeesAPreview() async throws {
        let remote = try #require(try await source().latestVersion(for: app(version: "4.7.4")))

        #expect(remote.displayVersion == "4.7.5")
        #expect(remote.releaseChannel == .stable)
        let items = try #require(remote.structuredChangelog?.entries.first?.items)
        #expect(items.contains { $0.contains("Stable-only QEMU update") })
        #expect(!items.contains { $0.contains("Beta-only") })
    }

    @Test func anUnknownInstalledTagFailsClosedInsteadOfGuessingStable() async throws {
        #expect(try await source().latestVersion(for: app(version: "9.9.9-local")) == nil)
    }

    @Test func missingReleaseStateFailsClosedInsteadOfMeaningStable() async throws {
        #expect(try await source().latestVersion(for: app(version: "5.0.3")) == nil)
    }

    /// A version that could never form a tag this rule accepts must not cost a
    /// request at all — a hand-built copy is checked as often as any other row.
    @Test func anUnusableInstalledVersionIsRejectedBeforeSpendingARequest() async throws {
        let source = self.source()
        #expect(try await source.latestVersion(for: app(version: "not-a-version")) == nil)
        #expect(FixtureProtocol.paths().isEmpty)
    }

    @Test func aProvenChannelIsRememberedInsteadOfReProvedOnEveryCheck() async throws {
        let store = tempStore()

        let first = try #require(try await source(channelStore: store)
            .latestVersion(for: app(version: "5.0.4")))
        #expect(first.releaseChannel == .beta)
        #expect(FixtureProtocol.paths().contains("/repos/utmapp/UTM/releases/tags/v5.0.4"))
        #expect(await store.channel(for: app(version: "5.0.4")) == .beta)

        let second = try #require(try await source(channelStore: store)
            .latestVersion(for: app(version: "5.0.4")))
        #expect(second.releaseChannel == .beta)
        #expect(!FixtureProtocol.paths().contains("/repos/utmapp/UTM/releases/tags/v5.0.4"),
                "a proof about one copy at one version does not need re-buying every check")
    }

    /// A stored proof must be scoped to the exact copy AND its exact version:
    /// the same path at a new version is a different install to classify.
    @Test func aRememberedChannelDoesNotSurviveTheCopyChangingVersion() async throws {
        let store = tempStore()
        await store.record(.beta, for: app(version: "5.0.4"))
        #expect(await store.channel(for: app(version: "5.0.4")) == .beta)
        #expect(await store.channel(for: app(version: "4.7.5")) == nil)
    }

    /// Two copies of one app can be installed at once on different channels —
    /// the development machine has exactly that. Keying by bundle id would make
    /// each row's badge depend on which copy was checked last.
    @Test func twoInstalledCopiesKeepSeparateProofs() async throws {
        let store = tempStore()
        let beta = InstalledApp(
            name: "UTM", bundleID: "com.utmapp.UTM", shortVersion: "5.0.5", buildVersion: "124",
            path: URL(fileURLWithPath: "/Applications/UTM.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
        let stable = InstalledApp(
            name: "UTM", bundleID: "com.utmapp.UTM", shortVersion: "4.7.5", buildVersion: "118",
            path: URL(fileURLWithPath: "/Users/someone/Applications/UTM.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)

        await store.record(.beta, for: beta)
        await store.record(.stable, for: stable)

        #expect(await store.channel(for: beta) == .beta)
        #expect(await store.channel(for: stable) == .stable)
    }

    /// The row identity has to survive a check that failed, or a network blip
    /// repaints a Beta row as an ordinary Stable one and files its notes under
    /// the wrong cache key.
    @Test func aFailedCheckKeepsTheChannelAnEarlierCheckProved() async throws {
        let store = tempStore()
        let installed = app(version: "5.0.4")
        await store.record(.beta, for: installed)

        let checker = UpdateChecker(sources: [], channelStore: store)
        let result = await checker.check(installed)

        #expect(result.remote == nil)
        #expect(result.effectiveReleaseChannel == .beta)
        #expect(UpdateResult(app: installed, remote: nil, status: .unknown)
                .effectiveReleaseChannel == .stable,
                "without the store there is nothing to fall back to — that is the bug this fixes")
    }

    /// A proof must not outlive its evidence. Note the scope of that: a stored
    /// proof is deliberately trusted without re-checking until the copy changes
    /// version — that is the whole saving — so this covers the case where there
    /// was nothing stored and the lookup failed to prove anything.
    @Test func aFailedProofStoresNothing() async throws {
        let store = tempStore()
        let installed = app(version: "5.0.3")  // the schema-drift fixture

        #expect(try await source(channelStore: store).latestVersion(for: installed) == nil)
        #expect(await store.channel(for: installed) == nil)
    }
}
