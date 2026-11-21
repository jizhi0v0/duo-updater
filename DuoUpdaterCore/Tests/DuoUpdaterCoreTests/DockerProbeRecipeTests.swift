import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite("Docker vendor probe")
struct DockerProbeRecipeTests {
    private static let bundleID = DockerDesktopChannel.bundleID
    private static let imageURL = "https://desktop.docker.com/mac/main/arm64/246961/Docker.dmg"
    private static let imageSHA256 = "633c570d2eda7e6100ff59080d065f185f27cd9d981b2b9b0ef68b9778e33cd9"
    private static let nightlyImageURL = "https://desktop-stage.docker.com/mac/main/arm64/247044/Docker.dmg"
    private static let nightlyImageSHA256 = "7f09fd58d1a540221079e29e07fe6846b46aa1e60c6dd92fcb08bea60a682fa5"

    // Trimmed from the stable ARM64 appcast fetched on 2026-11-20.
    private static let olderRelease = """
    {
        "Date": "2026-11-09T09:43:37Z",
        "PreviousBuild": "245422",
        "Visibility": "100",
        "AppVersion": "4.99.0",
        "BuildNumber": "245822",
        "MinOSVersion": "14.0.0",
        "Artifacts": [
            {
                "URL": "https://desktop.docker.com/mac/main/arm64/245822/Docker.dmg",
                "Length": "573453282",
                "Type": "dmg",
                "Checksum": "0ede7f9917b55c396a17b03c069cadf457a7d21904bc264c6d398fe132da7fb9"
            }
        ]
    }
    """

    private static let newerRelease = """
    {
        "Date": "2026-11-19T14:04:13Z",
        "PreviousBuild": "245822",
        "Visibility": "99",
        "AppVersion": "4.100.0",
        "BuildNumber": "246961",
        "MinOSVersion": "14.0.0",
        "Artifacts": [
            {
                "URL": "\(imageURL)",
                "Length": "573576477",
                "Type": "dmg",
                "Checksum": "\(imageSHA256)"
            },
            {
                "URL": "https://desktop.docker.com/mac/main/arm64/246961/Docker.pkg",
                "Length": "555414328",
                "Type": "pkg",
                "Checksum": "9c46bc8de01f70e8869d42da90ebf1ad79008eda131ad12e5d3c0e6c249bcc8c"
            }
        ]
    }
    """

    // Trimmed from the Nightly ARM64 appcast fetched on 2026-11-21.
    private static let nightlyVisible = """
    {
        "Date": "2026-11-20T04:20:15Z",
        "Visibility": "100",
        "AppVersion": "4.101.0",
        "BuildNumber": "247044",
        "MinOSVersion": "14.0.0",
        "Artifacts": [{"URL": "\(nightlyImageURL)", "Type": "dmg", "Checksum": "\(nightlyImageSHA256)"}]
    }
    """

    private static let nightlyHidden = """
    {
        "Date": "2026-11-20T17:17:13Z",
        "Visibility": "0",
        "AppVersion": "4.101.0",
        "BuildNumber": "247119",
        "MinOSVersion": "14.0.0",
        "Artifacts": [{"URL": "https://desktop-stage.docker.com/mac/main/arm64/247119/Docker.dmg",
                       "Type": "dmg", "Checksum": "56f83752a5bb2e4b7f1f3a0548c9978e9fcaf12741a33e235b0210bd8ea23b22"}]
    }
    """

    enum Feed: String {
        case captured, reversed, sameMarketing, hidden, newerNeedsOS, allNeedOS
        case wrongBuild, wrongArchitecture, wrongHost, wrongType, missingDigest, foreignDelta, malformed
        case nightly, stableWithNightlyImage, nightlyWithStableImage, nightlyRedirectedToStable

        var body: String {
            let older = DockerProbeRecipeTests.olderRelease
            let newer = DockerProbeRecipeTests.newerRelease
            let imageURL = DockerProbeRecipeTests.imageURL
            let nightly = DockerProbeRecipeTests.nightlyVisible
            let nightlyHidden = DockerProbeRecipeTests.nightlyHidden
            func appcast(_ first: String, _ second: String) -> String {
                #"{"Version":"1.0","Items":["# + first + "," + second + "]}"
            }
            switch self {
            case .captured: return appcast(older, newer)
            case .reversed: return appcast(newer, older)
            case .sameMarketing: return appcast(older.replacingOccurrences(of: "4.99.0", with: "4.100.0"), newer)
            case .hidden:
                return appcast(older, newer.replacingOccurrences(of: #""Visibility": "99""#, with: #""Visibility": "0""#))
            case .newerNeedsOS:
                return appcast(older, newer.replacingOccurrences(of: "14.0.0", with: "26.0"))
            case .allNeedOS: return appcast(older, newer).replacingOccurrences(of: "14.0.0", with: "26.0")
            case .wrongBuild:
                return appcast(older, newer.replacingOccurrences(
                    of: imageURL, with: "https://desktop.docker.com/mac/main/arm64/245822/Docker.dmg"))
            case .wrongArchitecture:
                return appcast(older, newer.replacingOccurrences(
                    of: imageURL, with: "https://desktop.docker.com/mac/main/amd64/246961/Docker.dmg"))
            case .wrongHost:
                return appcast(older, newer.replacingOccurrences(
                    of: "desktop.docker.com/mac/main/arm64/246961/Docker.dmg",
                    with: "desktop.docker.com.invalid/mac/main/arm64/246961/Docker.dmg"))
            case .wrongType:
                return appcast(older, newer.replacingOccurrences(of: #""Type": "dmg""#, with: #""Type": "delta""#))
            case .missingDigest:
                return appcast(older, newer.replacingOccurrences(of: DockerProbeRecipeTests.imageSHA256, with: ""))
            case .foreignDelta:
                return #"{"version":"4.100.0","deltas":[{"from":"245422","url":"https://other.invalid/update.delta"}],"#
                    + appcast(older, newer).dropFirst()
            case .malformed: return appcast(older, newer).replacingOccurrences(of: #""Items""#, with: #""PreviousItems""#)
            case .nightly: return appcast(nightlyHidden, nightly)
            case .stableWithNightlyImage:
                return appcast(older, newer.replacingOccurrences(of: "desktop.docker.com", with: "desktop-stage.docker.com"))
            case .nightlyWithStableImage:
                return appcast(nightlyHidden, nightly.replacingOccurrences(of: "desktop-stage.docker.com", with: "desktop.docker.com"))
            case .nightlyRedirectedToStable: return appcast(older, newer)
            }
        }
    }

    private final class AppcastProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
                return
            }
            let feed: Feed
            switch url.absoluteString {
            case "https://desktop.docker.com/mac/main/arm64/appcast.json": feed = .captured
            case "https://desktop-stage.docker.com/mac/main/arm64/appcast.json": feed = .nightly
            default:
                guard url.host == "docker-feed.fixture.invalid", let fixture = Feed(rawValue: url.lastPathComponent) else {
                    client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
                    return
                }
                feed = fixture
            }
            let responseURL = feed == .nightlyRedirectedToStable
                ? URL(string: "https://desktop.docker.com/mac/main/arm64/appcast.json")! : url
            let response = HTTPURLResponse(
                url: responseURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(feed.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppcastProtocol.self]
        return URLSession(configuration: config)
    }

    private func source(_ feed: Feed, hostOS: String = "15.0", channel: ReleaseChannel = .stable) throws -> VendorProbeSource {
        let recipe = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == Self.bundleID && $0.channel == channel
        })
        let endpoint = URL(string: "https://docker-feed.fixture.invalid/\(feed.rawValue)")!
        return VendorProbeSource(recipes: [recipe.with(url: endpoint)], session: session, hostOSVersion: hostOS)
    }

    private func installed(
        _ marketing: String = "4.98.0", _ build: String = "245422", channel: ReleaseChannel = .stable
    ) -> InstalledApp {
        InstalledApp(
            name: "Docker", bundleID: Self.bundleID, shortVersion: marketing, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZDockerFixture.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: channel)
    }

    @Test(arguments: [Feed.captured, .reversed, .sameMarketing])
    func reportsTheLatestReleaseAndItsOwnFullImage(_ feed: Feed) async throws {
        let source = try source(feed)
        let remote = try #require(try await source.latestVersion(for: installed()))
        #expect(remote.shortVersion == "4.100.0")
        #expect(remote.version == "246961")
        #expect(remote.marketingMatchesBundle)
        #expect(remote.downloadURL?.absoluteString == Self.imageURL)
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.expectedSHA256 == Self.imageSHA256)
        #expect(remote.expectedSHA512 == nil)
        #expect(remote.publishedAt != nil)
    }

    @Test func newerReleaseIsOfferedWithoutRequiringThePreviousBuild() async throws {
        let source = try source(.captured)
        for app in [installed(), installed("4.99.0", "245822"), installed("4.100.0", "246000")] {
            let remote = try #require(try await source.latestVersion(for: app))
            #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: "4.100.0"))
        }
        for app in [installed("4.100.0", "246961"), installed("4.101.0", "246000")] {
            let remote = try #require(try await source.latestVersion(for: app))
            #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
        }
    }

    @Test(arguments: [Feed.hidden, .newerNeedsOS])
    func choosesAnEligibleOlderRelease(_ feed: Feed) async throws {
        let remote = try #require(try await source(feed).latestVersion(for: installed()))
        #expect(remote.shortVersion == "4.99.0")
        #expect(remote.version == "245822")
        #expect(remote.downloadURL?.lastPathComponent == "Docker.dmg")
        #expect(remote.downloadURL?.deletingLastPathComponent().lastPathComponent == "245822")
    }

    @Test func refusesReleasesThatAllNeedNewerMacOS() async throws {
        let source = try source(.allNeedOS)
        await #expect(throws: OSWindowRefused.self) {
            try await source.latestVersion(for: installed())
        }
    }

    @Test(arguments: [Feed.wrongBuild, .wrongArchitecture, .wrongHost, .wrongType, .missingDigest])
    func detectsWithoutBorrowingAnotherArtifact(_ feed: Feed) async throws {
        let remote = try #require(try await source(feed).latestVersion(for: installed()))
        #expect(remote.shortVersion == "4.100.0")
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA256 == nil)
        #expect(remote.requiresManualInstaller)
    }

    @Test func unrelatedTopLevelDeltaCannotBecomeAnAlternateInstaller() async throws {
        let remote = try #require(try await source(.foreignDelta).latestVersion(for: installed()))
        #expect(remote.downloadURL?.absoluteString == Self.imageURL)
        #expect(remote.deltas.isEmpty)
    }

    @Test func malformedAppcastFailsTheProbe() async throws {
        let source = try source(.malformed)
        await #expect(throws: VendorProbeSource.ProbeFailed.self) {
            try await source.latestVersion(for: installed())
        }
    }

    @Test func nightlyCopyCannotUseTheStableRecipe() async throws {
        let source = try source(.captured)
        #expect(try await source.latestVersion(for: installed(channel: .nightly)) == nil)
    }

    @Test func eachChannelChecksItsRegisteredFeed() async throws {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(Set(recipes.map(\.recipeID)) == ["vendor:com.docker.docker:stable", "vendor:com.docker.docker:nightly"])
        let source = VendorProbeSource(recipes: recipes, session: session, hostOSVersion: "15.0")
        let stable = try #require(try await source.latestVersion(for: installed()))
        #expect(stable.version == "246961")
        #expect(stable.downloadURL?.absoluteString == Self.imageURL)
        #expect(stable.changelogURL != nil)

        let nightly = try #require(try await source.latestVersion(for: installed(channel: .nightly)))
        #expect(nightly.shortVersion == "4.101.0")
        #expect(nightly.version == "247044")
        #expect(nightly.downloadURL?.absoluteString == Self.nightlyImageURL)
        #expect(nightly.vendorInstallerKind == .dmg)
        #expect(nightly.expectedSHA256 == Self.nightlyImageSHA256)
        #expect(nightly.changelogURL == nil)
        #expect(nightly.deltas.isEmpty)
        #expect(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .nightly) == nil)
    }

    @Test(arguments: [(Feed.stableWithNightlyImage, ReleaseChannel.stable), (.nightlyWithStableImage, .nightly)])
    func rejectsAnArtifactFromTheOtherChannel(_ feed: Feed, channel: ReleaseChannel) async throws {
        let remote = try #require(try await source(feed, channel: channel).latestVersion(for: installed(channel: channel)))
        #expect(remote.version == (channel == .stable ? "246961" : "247044"))
        #expect(remote.vendorInstallerKind == nil)
        #expect(remote.expectedSHA256 == nil)
        #expect(remote.requiresManualInstaller)
    }

    @Test func rejectsANightlyFeedRedirectedToStable() async throws {
        let source = try source(.nightlyRedirectedToStable, channel: .nightly)
        await #expect(throws: VendorProbeSource.ProbeFailed.self) {
            try await source.latestVersion(for: installed(channel: .nightly))
        }
    }

    @Test(arguments: [
        (nil as String?, false),
        (#"{}"#, false),
        (#"{"UseNightlyBuildUpdates":false}"#, false),
        (#"{"UseNightlyBuildUpdates":true}"#, true),
        (#"{"UseNightlyBuildUpdates":"true"}"#, false),
        (#"{"UseNightlyBuildUpdates":1}"#, false),
        ("{", false),
        (#"{"AcceptCanaryUpdates":true}"#, false),
        (#"{"UseNightlyBuildUpdates":true,"AcceptCanaryUpdates":true}"#, true),
        (#"{"useNightlyBuildUpdates":true}"#, true),
        (#"{"useNightlyBuildUpdates":"true"}"#, false),
        (#"{"UseNightlyBuildUpdates":false,"useNightlyBuildUpdates":true}"#, false),
        (#"{"useNightlyBuildUpdates":true,"UseNightlyBuildUpdates":false}"#, false),
        (#"{"UseNightlyBuildUpdates":true,"useNightlyBuildUpdates":false}"#, true),
        (#"{"UseNightlyBuildUpdates":1,"useNightlyBuildUpdates":true}"#, false),
    ])
    func followsOnlyTheDockerNightlyBoolean(_ settings: String?, nightly: Bool) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        if let settings { try Data(settings.utf8).write(to: url) }
        let resolved = DockerDesktopChannel.resolve(settingsURL: url)
        #expect(resolved.channel == (nightly ? .nightly : .stable))
        #expect(resolved.feedOverride == nil)
    }
}
