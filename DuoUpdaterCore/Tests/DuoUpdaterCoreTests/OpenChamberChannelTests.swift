import Foundation
import Testing

@testable import DuoUpdaterCore

/// OpenChamber's `v2-preview` test builds, told apart from stable by the
/// `-preview.<N>` tail on their version — `ReleaseChannel.detect` step 4.
///
/// The inputs are each package's own Info.plist values: the preview build and
/// stable share `dev.openchamber.desktop`, the name "OpenChamber" and the Team,
/// and `CFBundleShortVersionString` = `CFBundleVersion` on both
/// (`2.0.0-preview.8`; `2.1.0`, `2.1.1`).
@Suite struct OpenChamberChannelTests {

    private static let bundleID = "dev.openchamber.desktop"

    private func detect(_ version: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "OpenChamber", bundleID: Self.bundleID, keystoneChannel: nil,
            version: version, bundleFileName: "OpenChamber")
    }

    @Test func thePreviewBuildReadsAsPreview() {
        #expect(detect("2.0.0-preview.8") == .preview)
    }

    @Test func theStableBuildsStayStable() {
        #expect(detect("2.1.0") == .stable)
        #expect(detect("2.1.1") == .stable)
    }

    /// The rule is a version shape, not an OpenChamber rule, so the shapes next
    /// to it are what keep it from reading build metadata as a channel. The whole
    /// string has to end at the counter, and the word has to be exactly `preview`.
    @Test func lookAlikesStayStable() {
        for version in [
            "2.0.0-preview",            // no counter
            "2.0.0-preview.8+9fba129",  // build metadata after the counter
            "2.0.0-preview.8.1",        // more than one counter
            "2.0.0-preview.x",          // non-numeric counter
            "2.0.0-previews.8",         // a different word
            "2.0.0-preview8",           // counter not dot-separated
            "preview.8",                // no numeric prefix
            "2.0.0.preview.8",          // no dash before the word
        ] {
            #expect(ReleaseChannel.detect(
                name: "App", bundleID: nil, keystoneChannel: nil, version: version) == .stable,
                "\(version)")
        }
    }

    /// A preview copy is offered nothing: the only GitHub rule for this app is
    /// stable, so the channel gate refuses it before any request is made, and the
    /// stable build is no longer offered to it.
    @Test func aPreviewCopyIsNotOfferedTheStableRelease() async throws {
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == Self.bundleID }
        #expect(rules.map(\.channel) == [.stable])

        RefuseAllRequests.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefuseAllRequests.self]
        let source = GitHubReleasesSource(
            rules: rules, session: URLSession(configuration: configuration))
        let app = InstalledApp(
            name: "OpenChamber", bundleID: Self.bundleID,
            shortVersion: "2.0.0-preview.8", buildVersion: "2.0.0-preview.8",
            path: URL(fileURLWithPath: "/Applications/OpenChamber.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil,
            releaseChannel: detect("2.0.0-preview.8"))

        #expect(try await source.latestVersion(for: app) == nil)
        #expect(RefuseAllRequests.count == 0)
    }
}

/// Fails every request and counts them, so a test can tell "refused before the
/// network" from "asked and got nothing".
private final class RefuseAllRequests: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen = 0

    static func reset() { lock.withLock { seen = 0 } }
    static var count: Int { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.seen += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
