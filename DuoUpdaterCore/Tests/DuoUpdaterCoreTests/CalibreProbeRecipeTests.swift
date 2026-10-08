import Testing
import Foundation
@testable import DuoUpdaterCore

/// `calibre-ebook.com/latest-version` as served on 2026-10-08: the whole body is
/// these six bytes, with no trailing newline.
private let calibreLatestVersionBody = "9.15.0"

/// The direct-download Calibre probe, and the order that keeps it away from a
/// copy Homebrew installed. Driven through the real `UpdateChecker` with a local
/// stub for the vendor endpoint, so no request leaves the machine.
struct CalibreProbeRecipeTests {

    private static let bundleID = "net.kovidgoyal.calibre"
    private static let endpoint = URL(string: "https://calibre-ebook.com/latest-version")!

    private final class DocumentServer: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var documents: [String: String] = [:]

        static func serve(_ url: URL, _ body: String) {
            lock.lock(); defer { lock.unlock() }
            documents[url.absoluteString] = body
        }

        private static func document(_ url: URL) -> String? {
            lock.lock(); defer { lock.unlock() }
            return documents[url.absoluteString]
        }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DocumentServer.self]
            return URLSession(configuration: configuration)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url, let body = Self.document(url) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static func registered() throws -> VendorProbeRecipe {
        let recipes = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }
        try #require(recipes.count == 1)
        return recipes[0]
    }

    private static func app(version: String) -> InstalledApp {
        InstalledApp(
            name: "calibre", bundleID: bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/calibre.app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    /// Homebrew's view of the same app: the `calibre` cask, not `auto_updates`.
    private static func homebrew(installed: Bool) -> HomebrewCaskSource {
        let entry = CaskEntry(
            token: "calibre", version: "9.15.0",
            url: URL(string: "https://download.calibre-ebook.com/9.15.0/calibre-9.15.0.dmg"),
            autoUpdates: false, installKind: .brew)
        return HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: CaskIndex(
                allByAppFilename: ["calibre.app": [entry]], allByBundleID: [:])),
            inventory: BrewLocalInventory(installedTokens: installed ? ["calibre"] : []),
            hostOSVersion: "26.0")
    }

    private static func checker(homebrewInstalled: Bool, vendorBody: String) throws -> UpdateChecker {
        DocumentServer.serve(endpoint, vendorBody)
        return UpdateChecker(sources: [
            homebrew(installed: homebrewInstalled),
            VendorProbeSource(
                recipes: [try registered()], session: DocumentServer.session(),
                hostOSVersion: "26.0", resolvesInstallRedirects: false),
        ])
    }

    @Test func readsTheStableVersionOffTheVendorsEndpoint() throws {
        let recipe = try Self.registered()
        #expect(recipe.url == Self.endpoint)
        #expect(recipe.channel == .stable)
        #expect(VendorProbeRecipe.extractVersion(
            from: calibreLatestVersionBody, pattern: recipe.versionPattern) == "9.15.0")
        #expect(VendorProbeRecipe.extractVersion(
            from: calibreLatestVersionBody + "\n", pattern: recipe.versionPattern) == "9.15.0")
        // A preview number, or anything that is not the bare version, is no answer.
        for body in ["9.15.101", "<html><body>9.15.0</body></html>", "calibre 9.15.0"] {
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == nil,
                    "\(body)")
        }
    }

    /// One-click from the vendor's own host, never the GitHub asset.
    @Test func installsTheDmgFromTheVendorsHost() throws {
        let spec = try #require(try Self.registered().install)
        #expect(spec.kind == .dmg)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("expected a version template, got \(spec.urlSource)")
            return
        }
        #expect(template.replacingOccurrences(of: "{version}", with: "9.15.0")
            == "https://download.calibre-ebook.com/9.15.0/calibre-9.15.0.dmg")
    }

    @Test func onlyRunsWhereTheVendorSaysCalibreRuns() throws {
        let recipe = try Self.registered()
        #expect(recipe.runs(onOS: "14.0", arch: .arm64))
        #expect(recipe.runs(onOS: "14.0", arch: .x86_64))
        #expect(!recipe.runs(onOS: "13.7.8", arch: .arm64))
    }

    /// A preview copy (`x.y.1nn`) is not a stable copy: no stable offer reaches it.
    @Test func previewCopiesAreNotThisRecipes() throws {
        let recipe = try Self.registered()
        for version in ["9.15.0", "9.14.0", "7.26.0"] {
            #expect(recipe.matchesInstalled(version: version), "\(version)")
        }
        for version in ["9.15.101", "9.9.105"] {
            #expect(!recipe.matchesInstalled(version: version), "\(version)")
        }
    }

    /// A copy installed from the vendor's dmg: Homebrew declines it, and the
    /// probe answers with the vendor's version and dmg.
    @Test func aDirectCopyIsAnsweredByTheProbe() async throws {
        let result = try await Self.checker(homebrewInstalled: false, vendorBody: "9.16.0")
            .check(Self.app(version: "9.15.0"))
        #expect(result.remote?.sourceName == VendorProbeSource.sourceName)
        #expect(result.remote?.shortVersion == "9.16.0")
        #expect(result.remote?.downloadURL?.absoluteString
            == "https://download.calibre-ebook.com/9.16.0/calibre-9.16.0.dmg")
        #expect(result.status == .updateAvailable(latest: "9.16.0"))
    }

    /// A copy Homebrew installed keeps going through Homebrew, even while the
    /// vendor's endpoint is a release ahead of the cask.
    @Test func aBrewCopyStaysWithHomebrew() async throws {
        let result = try await Self.checker(homebrewInstalled: true, vendorBody: "9.16.0")
            .check(Self.app(version: "9.15.0"))
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.remote?.shortVersion == "9.15.0")
        #expect(result.status == .upToDate)
    }

    @Test func aPreviewCopyIsNotOfferedTheStableRelease() async throws {
        let result = try await Self.checker(homebrewInstalled: false, vendorBody: "9.16.0")
            .check(Self.app(version: "9.15.101"))
        #expect(result.remote == nil)
    }

    /// The order the two tests above depend on, read from the production stack.
    @Test func homebrewIsAskedBeforeTheVendorProbe() {
        let names = SourceStack.make(githubToken: nil).map { String(describing: type(of: $0)) }
        let homebrew = names.firstIndex(of: "HomebrewCaskSource")
        let vendor = names.firstIndex(of: "VendorProbeSource")
        #expect(homebrew != nil && vendor != nil, "stack: \(names)")
        if let homebrew, let vendor { #expect(homebrew < vendor, "stack: \(names)") }
    }
}
