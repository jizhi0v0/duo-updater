import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

// `Verify.edgeCopyComplaint` end to end: a real `VendorProbeSource` probe against
// a stubbed CDN, twice — once as the sweep asks, once with the `noCache` query.
//
// Not covered here: that `sweepVendor` calls it at all. The sweep runs the live
// registry over the network, so dropping that call would leave these green.

/// A CDN in two moods, chosen by host. `edge-copy.invalid` answers the bare
/// address from a stale copy and a request carrying a query from the origin —
/// Kimi's manifest host, 2026-09-11. `in-sync.invalid` serves one document either
/// way. Stateless, so the parallel runner cannot trip over it.
private final class EdgeCDNProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["edge-copy.invalid", "in-sync.invalid"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let stale = url.host == "edge-copy.invalid" && url.query == nil
        let body = "version: \(stale ? "3.2.5" : "3.2.7")\n"
            + "files:\n  - url: App-\(stale ? "3.2.5" : "3.2.7")-arm64-mac.zip\n"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/yaml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func manifestRecipe(host: String) -> VendorProbeRecipe {
    VendorProbeRecipe(
        bundleID: "com.duoupdater.test.edgecopy.\(host)",
        url: URL(string: "https://\(host)/app/upgrade/latest-mac.yml")!,
        mode: .responseBody,
        versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#)
}

private func stubbedSource(_ recipe: VendorProbeRecipe) -> VendorProbeSource {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EdgeCDNProtocol.self]
    return VendorProbeSource(recipes: [recipe], session: URLSession(configuration: configuration))
}

@Test func aStaleEdgeCopyIsReportedAgainstTheOrigin() async throws {
    let recipe = manifestRecipe(host: "edge-copy.invalid")
    #expect(RecipeSanity.readsElectronManifest(recipe))
    let source = stubbedSource(recipe)

    // What the sweep itself reads: the bare address, and so the stale copy.
    let bare = await source.probeDiagnostic(recipe)
    let bareVersion = try #require(bare.remote?.shortVersion ?? bare.remote?.version)
    #expect(bareVersion == "3.2.5")

    let complaint = try #require(
        await Verify.edgeCopyComplaint(recipe, bareVersion: bareVersion, source: source))
    #expect(complaint.contains("3.2.5") && complaint.contains("3.2.7"))
}

@Test func anEndpointThatAgreesWithItselfStaysQuiet() async throws {
    let recipe = manifestRecipe(host: "in-sync.invalid")
    let source = stubbedSource(recipe)
    let bare = await source.probeDiagnostic(recipe)
    let bareVersion = try #require(bare.remote?.shortVersion ?? bare.remote?.version)
    #expect(bareVersion == "3.2.7")
    #expect(await Verify.edgeCopyComplaint(recipe, bareVersion: bareVersion, source: source) == nil)
}
