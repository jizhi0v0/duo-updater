import Testing
import Foundation
@testable import DuoUpdaterCore

/// Aside's `version_info.json`, captured verbatim on 2026-09-14 (the whole body is
/// 244 bytes). The two platforms were on different builds that day, which is the
/// case the recipe has to get right: the Mac was offered 1.0.910.1.
private let asideVersionInfo = #"""
{"platforms":{"mac":{"version":"1.0.910.1","url":"https://releases.aside.com/dev-updater/Aside-1.0.910.1.dmg"},"win":{"version":"1.0.914.1","url":"https://releases.aside.com/dev-updater/windows/1.0.914.1/AsideInstaller-1.0.914.1-win-x64.exe"}}}
"""#

/// The same document with the platforms and the Mac object's keys in the other
/// order. Synthetic: the service has not been observed answering this way, but
/// JSON key order is not something it promised.
private let asideWindowsFirst = #"""
{"platforms":{"win":{"version":"1.0.914.1","url":"https://releases.aside.com/dev-updater/windows/1.0.914.1/AsideInstaller-1.0.914.1-win-x64.exe"},"mac":{"url":"https://releases.aside.com/dev-updater/Aside-1.0.910.1.dmg","version":"1.0.910.1"}}}
"""#

/// Synthetic: a Mac object that has lost its version while Windows still carries
/// one. The only version left in the body is a build the Mac cannot download.
private let asideMacWithoutVersion = #"""
{"platforms":{"mac":{"url":"https://releases.aside.com/dev-updater/Aside-1.0.910.1.dmg"},"win":{"version":"1.0.914.1","url":"https://releases.aside.com/dev-updater/windows/1.0.914.1/AsideInstaller-1.0.914.1-win-x64.exe"}}}
"""#

/// Driven through the real `probeOutcome` against a local stub, with the
/// registry's own recipe copied onto a per-test host, so the scoping every reader
/// goes through (`entryStartPattern`, `selectHighest`) is the production one.
struct AsideProbeRecipeTests {

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
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "at.studio.AsideBrowser" })
    }

    private static func probe(_ body: String, host: String) async throws -> ProbeOutcome {
        let registered = try registered()
        let url = URL(string: "https://\(host)/version_info.json")!
        DocumentServer.serve(url, body)
        let recipe = VendorProbeRecipe(
            bundleID: registered.bundleID, url: url, mode: registered.mode,
            versionPattern: registered.versionPattern,
            downloadURL: registered.downloadURL, changelogURL: registered.changelogURL,
            selectHighest: registered.selectHighest,
            versionIsBuild: registered.versionIsBuild,
            entryStartPattern: registered.entryStartPattern,
            install: registered.install)
        return await VendorProbeSource(recipes: [], session: DocumentServer.session())
            .probeOutcome(recipe)
    }

    @Test func readsTheMacBuildOffTheVendorsVersionFile() async throws {
        let registered = try Self.registered()
        #expect(registered.url.absoluteString
            == "https://ptqgesmtzwdmeiknncqc.supabase.co/functions/v1/omaha/version_info.json")
        // Detection-only until someone checks the app's own updater against a swap.
        #expect(registered.install == nil)

        let outcome = try await Self.probe(asideVersionInfo, host: "real.aside.invalid")
        #expect(outcome.failure == nil)
        // The marketing string, as `CFBundleShortVersionString` reads on that build.
        #expect(outcome.remote?.displayVersion == "1.0.910.1")
    }

    @Test func theWindowsBuildDoesNotAnswerForTheMacWhateverTheKeyOrder() async throws {
        let outcome = try await Self.probe(asideWindowsFirst, host: "reordered.aside.invalid")
        #expect(outcome.remote?.displayVersion == "1.0.910.1")
    }

    /// The fence is `[^{}]*?`, not `.*?`: a lazy dot would walk out of the Mac
    /// object and report Windows' version as the Mac's.
    @Test func aMacObjectWithoutAVersionIsNoAnswerRatherThanWindowsVersion() async throws {
        let outcome = try await Self.probe(asideMacWithoutVersion, host: "nomac.aside.invalid")
        #expect(outcome.remote == nil)
        guard case .versionPatternNoMatch? = outcome.failure else {
            Issue.record("expected versionPatternNoMatch, got \(String(describing: outcome.failure))")
            return
        }
    }
}
