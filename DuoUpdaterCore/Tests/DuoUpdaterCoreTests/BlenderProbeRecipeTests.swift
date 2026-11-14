import Foundation
import Testing
@testable import DuoUpdaterCore

/// Representative entries of the mirror's JSON (`Accept: application/json`),
/// captured 2026-11-15. Extra versions below exercise ordering and GA filtering.
private let blenderMirrorIndex = #"""
[{"name":"Blender5.2/","url":"./Blender5.2/","is_dir":true},
 {"name":"Blender5.3/","url":"./Blender5.3/","is_dir":true},
 {"name":"Blender4.5/","url":"./Blender4.5/","is_dir":true}]
"""#
private let blenderMirrorFiles = #"""
[{"name":"blender-5.3.0-macos-arm64.dmg","url":"./blender-5.3.0-macos-arm64.dmg","is_dir":false},
 {"name":"blender-5.3.2-macos-arm64.dmg","url":"./blender-5.3.2-macos-arm64.dmg","is_dir":false},
 {"name":"blender-5.3.9-beta-macos-arm64.dmg","url":"./blender-5.3.9-beta-macos-arm64.dmg","is_dir":false},
 {"name":"blender-5.3.8-macos-x64.dmg","url":"./blender-5.3.8-macos-x64.dmg","is_dir":false},
 {"name":"blender-5.3.1-macos-arm64.dmg","url":"./blender-5.3.1-macos-arm64.dmg","is_dir":false}]
"""#

@Suite(.serialized)
struct BlenderProbeRecipeTests {
    private var recipe: VendorProbeRecipe {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.blenderfoundation.blender" && $0.channel == .stable }!
    }

    private final class Server: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var responses: [String: (Int, String)] = [:]
        nonisolated(unsafe) private static var seen: [URLRequest] = []
        static func serve(_ responses: [String: (Int, String)]) -> URLSession {
            lock.withLock { Self.responses = responses; seen = [] }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Self.self]
            return URLSession(configuration: config)
        }
        static var requests: [URLRequest] { lock.withLock { seen } }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let value = Self.lock.withLock {
                Self.seen.append(request)
                return Self.responses[request.url!.path] ?? (404, "unexpected path")
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: value.0, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(value.1.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test func fetchesNewestMinorThenNewestGAWithMatchingInstaller() async throws {
        let session = Server.serve([
            "/release": (200, blenderMirrorIndex),
            "/release/Blender5.3": (200, blenderMirrorFiles)])
        let result = await VendorProbeSource(session: session).probeOutcome(recipe)
        #expect(result.failure == nil)
        let remote = try #require(result.remote)
        #expect(remote.shortVersion == "5.3.2")
        #expect(remote.downloadURL?.absoluteString == "https://download.blender.org/release/Blender5.3/blender-5.3.2-macos-arm64.dmg")
        #expect(Server.requests.map { $0.url!.path } == ["/release", "/release/Blender5.3"])
        for request in Server.requests {
            #expect(request.cachePolicy == URLRequest.versionFeedCachePolicy)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.httpMethod == "GET")
        }
    }

    @Test(arguments: [(200, "[]"), (403, "forbidden"), (200, #"[{"name":"preview","url":"./blender-5.3.9-beta-macos-arm64.dmg"}]"#)])
    func newestDirectoryCannotFallBackToAnOlderMinor(_ status: Int, _ body: String) async {
        let session = Server.serve([
            "/release": (200, blenderMirrorIndex),
            "/release/Blender5.3": (status, body),
            "/release/Blender5.2": (200, blenderMirrorFiles)])
        let result = await VendorProbeSource(session: session).probeOutcome(recipe)
        #expect(result.remote == nil)
        #expect(result.failure != nil)
        #expect(Server.requests.map { $0.url!.path } == ["/release", "/release/Blender5.3"])
    }

    @Test func numericDirectoryOrdering() throws {
        guard case .versionedDirectory(let pattern) = recipe.mode else {
            Issue.record("expected versioned directory"); return
        }
        let index = blenderMirrorIndex.replacingOccurrences(of: "5.2", with: "5.10").replacingOccurrences(of: "5.3", with: "5.9")
        #expect(VendorProbeSource.highestVersionedDirectory(in: index, pattern: pattern, root: recipe.url)?.path == "/release/Blender5.10")
    }

    @Test(arguments: ["../", "a/../", "https://evil.invalid/", "//evil.invalid/", "%2e%2e/", "a%2fb/", "a?x/", "a#x/", "a\\b/"])
    func refusesUntrustedChildLinks(_ path: String) {
        #expect(VendorProbeSource.highestVersionedDirectory(
            in: "link=\(path);version=5.3", pattern: #"link=(.*);version=(.*)"#, root: recipe.url) == nil)
    }

    @Test func indexShapeChangesFailBeforeAnotherRequest() async {
        let session = Server.serve(["/release": (200, "<html>challenge</html>")])
        let result = await VendorProbeSource(session: session).probeOutcome(recipe)
        #expect(result.remote == nil)
        #expect(result.failure?.kind == "versionPatternNoMatch")
        #expect(Server.requests.count == 1)
    }

    @Test func childEntryShapeChangesFailInsteadOfUsingTheFirstInstaller() async {
        let changed = blenderMirrorFiles.replacingOccurrences(of: "{\"name\":", with: "{\"renamed\":")
        let session = Server.serve([
            "/release": (200, blenderMirrorIndex),
            "/release/Blender5.3": (200, changed)])
        let result = await VendorProbeSource(session: session).probeOutcome(recipe)
        #expect(result.remote == nil)
        #expect(result.failure?.kind == "versionPatternNoMatch")
    }

    @Test func versionedDirectoryRecipesUseGETDirectoryEndpoints() throws {
        let recipes = VendorProbeRegistry.recipes.filter {
            if case .versionedDirectory = $0.mode { return true }; return false
        }
        #expect(!recipes.isEmpty)
        for recipe in recipes {
            #expect(recipe.requestBody == nil)
            #expect(recipe.url.hasDirectoryPath)
            #expect(recipe.url.query == nil)
            #expect(recipe.url.fragment == nil)
            guard case .versionedDirectory(let pattern) = recipe.mode else { continue }
            #expect(try NSRegularExpression(pattern: pattern).numberOfCaptureGroups == 2)
        }
    }

    @Test func runsOnlyOnAppleSiliconAndLeavesBuilderTracksSeparate() {
        #expect(recipe.hostRequirement?.architectures == [.arm64])
        let previews = VendorProbeRegistry.recipes.filter { $0.bundleID == recipe.bundleID && $0.channel != .stable }
        #expect(Set(previews.map(\.channel)) == [.alpha, .beta, .rc])
        #expect(previews.allSatisfy { $0.url.host == "builder.blender.org" })
    }
}
