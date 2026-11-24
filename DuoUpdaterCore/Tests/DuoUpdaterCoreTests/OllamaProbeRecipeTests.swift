import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite("Ollama official updater")
struct OllamaProbeRecipeTests {
    private static let bundleID = "com.electron.ollama"
    private static let stableURL = "https://github.com/ollama/ollama/releases/download/v0.40.17/Ollama-darwin.zip"
    private static let previewURL = "https://github.com/ollama/ollama/releases/download/v0.40.18/Ollama-darwin.zip"
    private static let candidateURL = "https://github.com/ollama/ollama/releases/download/v0.40.18-rc0/Ollama-darwin.zip"

    private final class UpdateProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url,
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  url.host == "ollama.com", url.path == "/api/update", request.httpMethod == "GET",
                  query.filter({ $0.name != "version" && $0.name != "channel" }) == [
                      URLQueryItem(name: "os", value: "darwin"), URLQueryItem(name: "arch", value: "arm64")
                  ],
                  query.filter({ $0.name == "version" }).count <= 1,
                  query.filter({ $0.name == "channel" }) == []
                    || query.filter({ $0.name == "channel" }) == [URLQueryItem(name: "channel", value: "preview")] else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            let status: Int
            let body: String
            let track = query.first { $0.name == "channel" }?.value
            let version = query.first { $0.name == "version" }?.value
            switch (track, version) {
            case ("preview", "0.40.18"):
                (status, body) = (204, "")
            case ("preview", nil), ("preview", "0.40.16"), ("preview", "0.40.17"), ("preview", "0.40.18-rc0"):
                (status, body) = (200, #"{"url": "\#(previewURL)"}"#)
            case (nil, nil), (nil, "0.40.16"):
                // Captured from the public macOS update API.
                (status, body) = (200, #"{"url": "\#(stableURL)"}"#)
            case (nil, "0.40.17"), (nil, "0.40.18-rc0"), (nil, "0.40.18"):
                (status, body) = (204, "")
            case (nil, "0.40.15"):
                // The same URL shape is served when the vendor authorizes a preview.
                (status, body) = (200, #"{"url": "\#(candidateURL)"}"#)
            case (nil, "0.40.14"):
                (status, body) = (200, #"{"url": "https://github.com/other/ollama/releases/download/v0.40.17/Ollama-darwin.zip"}"#)
            case (nil, "0.40.12"):
                (status, body) = (200, #"{"url": "\#(stableURL)""#)
            case (nil, "0.40.11"):
                (status, body) = (206, #"{"url": "\#(stableURL)"}"#)
            case (nil, "0.40.10"):
                (status, body) = (200, #"{"other": {"url": "\#(candidateURL)"}, "url": "\#(stableURL)"}"#)
            case (nil, "0.40.9"):
                (status, body) = (200, #"{"other": {"url": "\#(candidateURL)"}}"#)
            case (nil, "0.40.16+build") where url.absoluteString.contains("version=0.40.16%2Bbuild"):
                (status, body) = (200, #"{"url": "\#(stableURL)"}"#)
            default:
                (status, body) = (200, "")
            }
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func source() -> VendorProbeSource {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateProtocol.self]
        return VendorProbeSource(recipes: recipes, session: URLSession(configuration: configuration))
    }

    private func app(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Ollama", bundleID: Self.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/Ollama.fixture.app"), isMASApp: false,
            sparkleFeedURL: nil,
            releaseChannel: .stable, channelIsAuthoritative: true)
    }

    @Test func installedVersionGetsTheVendorsExactArtifact() async throws {
        let source = source()
        let result = await UpdateChecker(sources: [source]).check(app("0.40.16"))
        #expect(result.hasUpdate)
        #expect(result.remote?.shortVersion == "0.40.17")
        #expect(result.remote?.downloadURL?.absoluteString == Self.stableURL)
        #expect(result.remote?.vendorInstallerKind == .zip)
    }

    @Test(arguments: ["0.40.17", "0.40.18-rc0"])
    func noContentMeansCurrentForTheQueriedCopy(version: String) async throws {
        let source = source()
        let result = await UpdateChecker(sources: [source]).check(app(version))
        #expect(result.status == .upToDate)
        #expect(result.remote?.noOfferForInstalledVersion == version)
        #expect(result.remote?.versionSide.isEmpty == true)
        #expect(result.remote?.downloadURL == nil)
        #expect(result.remote?.vendorInstallerKind == nil)
    }

    @Test func noContentDuringPreflightClearsAnEarlierOffer() async throws {
        let source = source()
        let copy = app("0.40.17")
        let offer = RemoteVersion(
            shortVersion: "0.40.18", version: nil, downloadURL: URL(string: Self.previewURL),
            sourceName: "Vendor", vendorInstallerKind: .zip)
        let offered = UpdateResult(app: copy, remote: offer, status: .updateAvailable(latest: "0.40.18"))
        let confirmed = await UpdateChecker(sources: [source]).check(copy)

        #expect(PreInstallGate.decision(offered: offered, confirmed: confirmed) == .alreadyCurrent)
        #expect(confirmed.remote?.versionSide.isEmpty == true)
    }

    @Test func offeredPrereleaseKeepsItsSuffix() async throws {
        let source = source()
        let result = await UpdateChecker(sources: [source]).check(app("0.40.15"))
        #expect(result.hasUpdate)
        #expect(result.remote?.shortVersion == "0.40.18-rc0")
        #expect(result.remote?.downloadURL?.absoluteString == Self.candidateURL)
    }

    @Test(arguments: ["0.40.14", "0.40.13", "0.40.12", "0.40.9"])
    func malformedSuccessDoesNotBecomeUpToDate(version: String) async throws {
        let source = source()
        let outcome = await source.probeDiagnostic(for: app(version))
        #expect(outcome?.succeeded == false)
        #expect(outcome?.failure?.kind == "versionPatternNoMatch")
    }

    @Test func partialHTTPResponseDoesNotOfferAnInstall() async throws {
        let source = source()
        let outcome = await source.probeDiagnostic(for: app("0.40.11"))
        #expect(outcome?.failure == .httpStatus(206))
    }

    @Test(arguments: ["0.40.10", "0.40.16+build"])
    func usesTopLevelURLAndSendsTheFullVersion(version: String) async throws {
        let source = source()
        let outcome = await source.probeDiagnostic(for: app(version))
        #expect(outcome?.remote?.shortVersion == "0.40.17")
        #expect(outcome?.remote?.downloadURL?.absoluteString == Self.stableURL)
    }

    @Test(arguments: ["0.40.17", "0.40.18-rc0"])
    func scannedBundleFollowsTheNativeUpdater(version: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollama-native-updater-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("Ollama Preview.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": Self.bundleID, "CFBundleName": "Ollama",
            "CFBundleShortVersionString": version, "CFBundleVersion": version,
            "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let scanner = AppScanner(locations: [directory], testflight: TestFlightInventory(macRows: []))
        let copy = try #require(scanner.scan(bundlesAt: [bundle]).first)
        #expect(copy.releaseChannel == .stable)
        #expect(copy.shortVersion == version)
        let source = source()
        let result = await UpdateChecker(sources: [source]).check(copy)
        #expect(result.status == .upToDate)
        #expect(result.remote?.noOfferForInstalledVersion == version)
    }

    private struct StableCask: UpdateSource {
        let name = "Homebrew"

        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            var remote = RemoteVersion(
                shortVersion: "0.40.17", version: nil, downloadURL: URL(string: stableURL),
                sourceName: name, sourceIdentifier: "ollama-app")
            remote.homebrewSelfUpdating = true
            remote.offeredChannel = .stable
            return remote
        }
    }

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func verificationCanResolveTheArtifactWithoutAnInstalledCopy(channel: ReleaseChannel) async throws {
        let source = source()
        let recipe = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == Self.bundleID && $0.channel == channel
        })
        let outcome = await source.probeDiagnostic(recipe)
        #expect(outcome.remote?.shortVersion == (channel == .stable ? "0.40.17" : "0.40.18"))
        #expect(outcome.remote?.downloadURL?.absoluteString == (channel == .stable ? Self.stableURL : Self.previewURL))
    }

    @Test func signingRefusalDoesNotSuppressAnExplicitNoOffer() async throws {
        let source = source()
        let copy = app("0.40.18")
        let key = InstallPreferenceKey.key(for: copy)
        let policy = BrewFallbackPolicy(
            signingRefusals: [key: .init(team: "3MU9H2V9Y9", version: "0.40.18")])
        let result = await UpdateChecker(
            sources: [StableCask(), source], brewFallback: policy,
            installedTeam: { _ in "3MU9H2V9Y9" }).check(copy)
        #expect(result.status == .upToDate)
        #expect(result.remote?.noOfferForInstalledVersion == "0.40.18")
        #expect(!result.brewFallbackWithheldForSigning)
    }
}
