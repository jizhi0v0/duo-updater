import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ToolboxSource` decides whether a Toolbox-managed app has an update. Two
/// behaviours are easy to get wrong and have no network in their path:
///   - "keep version" pins must suppress cross-line updates (a kept Android
///     Studio 2025.2.x must not surface the 2025.3 release).
///   - the verbose `displayVersion` Toolbox stores must reduce to a clean number.

private func app(at path: String) -> InstalledApp {
    InstalledApp(
        name: "Android Studio", bundleID: "com.google.android.studio",
        shortVersion: "2025.2", buildVersion: "252.0",
        path: URL(fileURLWithPath: path),
        isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil)
}

private func source(tool: ToolboxInventory.Tool, at path: String) -> ToolboxSource {
    ToolboxSource(inventory: ToolboxInventory(managedPaths: [path], tools: [path: tool]))
}

/// The pin rules run on whatever a live query returned, so they're tested against
/// `verdict(latestBuild:…)` directly — the network-free half of the source.
private func pinnedTool(line: String?) -> ToolboxInventory.Tool {
    ToolboxInventory.Tool(
        productCode: "AI", channelType: "release", installedBuild: "252.28238.7",
        isNewestOfProduct: false, displayVersion: "2025.2.3", pinnedLine: line)
}

@Test func pinnedToolSuppressesCrossLineUpdate() {
    // Kept on the 2025.2.3 line (build branch 252); the feed offers a 2025.3 build
    // (branch 253) — that crosses the pin and must be suppressed.
    let verdict = ToolboxSource.verdict(
        latestBuild: "253.5", display: "2025.3.4", tool: pinnedTool(line: "2025.2.3"))
    #expect(verdict.hasUpdate == false)
    // And reports the installed version, not the phantom 2025.3.4.
    #expect(verdict.latestVersion == "2025.2.3")
}

@Test func pinnedToolStillSurfacesInLinePatch() {
    // A same-line patch (252 → 252, newer build) is what the pin allows.
    let verdict = ToolboxSource.verdict(
        latestBuild: "252.99999.9", display: "2025.2.4", tool: pinnedTool(line: "2025.2.3"))
    #expect(verdict.hasUpdate == true)
}

@Test func unpinnedToolReportsCrossLineUpdate() {
    // No pin → the cross-line build is a real update.
    let verdict = ToolboxSource.verdict(
        latestBuild: "253.5", display: "2025.3.4", tool: pinnedTool(line: nil))
    #expect(verdict.hasUpdate == true)
    #expect(verdict.latestVersion == "2025.3.4")
}

/// A retained older copy of a product (a kept Koala beside the current Android
/// Studio) never queries the live feed — and must ABSTAIN rather than claim to be
/// up to date, which is what reading Toolbox's install history back as "latest"
/// used to do. Nil → the row shows a plain "managed by Toolbox".
@Test func retainedOlderCopyAbstainsInsteadOfClaimingUpToDate() async {
    let path = "/Users/x/Applications/Android Studio Koala.app"
    let tool = ToolboxInventory.Tool(
        productCode: "AI", channelType: "release", installedBuild: "241.1.1",
        isNewestOfProduct: false, displayVersion: "2024.1.2", pinnedLine: nil)
    #expect(await source(tool: tool, at: path).verdict(for: app(at: path)) == nil)
}

@Test func airRetargetsFeedToToolboxChannel() {
    // The build hardcodes the 'nightly' feed; Toolbox tracks Public Preview
    // ("eap"). Retargeting must swap only the channel segment.
    let nightly = URL(string:
        "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/nightly/macos_aarch64/feed.xml")!
    let eap = ToolboxSource.retargetChannel(nightly, to: "eap")
    #expect(eap?.absoluteString ==
        "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml")
}

@Test func airWithoutFeedDefersToToolbox() async {
    // No Sparkle feed and no product code → nothing to compare, defer to Toolbox.
    // `installedBuild` is Toolbox's `buildNumber` — the managed Public Preview
    // build, in the feed's namespace — while the bundle's own 261.617 is the
    // divergent SHIP runtime track.
    let path = "/Users/x/Applications/Air.app"
    let tool = ToolboxInventory.Tool(
        productCode: nil, channelType: "eap", installedBuild: "261.474.25",
        displayVersion: "261.474", pinnedLine: nil)
    let air = InstalledApp(
        name: "Air", bundleID: nil, shortVersion: "261.474", buildVersion: "261.617",
        path: URL(fileURLWithPath: path), isMASApp: false, isToolboxManaged: true,
        sparkleFeedURL: nil)
    let verdict = await source(tool: tool, at: path).verdict(for: air)
    #expect(verdict == nil)
}

@Test func jetbrainsVerdictCarriesReleaseNotesLink() async throws {
    // Live: a Toolbox-managed IntelliJ EAP must come back with the build's
    // YouTrack release-notes link from the JetBrains releases API, so the UI can
    // show real notes for an IDE that has no structured ChangelogRecipe. Network
    // gates this like the other live API tests; a transient failure → nil verdict,
    // which we skip rather than fail.
    let path = "/Users/x/Applications/IntelliJ IDEA 2026.2 EAP.app"
    let tool = ToolboxInventory.Tool(
        productCode: "IU", channelType: "eap", installedBuild: "262.1.1",
        displayVersion: "2026.2", pinnedLine: nil)
    let eap = InstalledApp(
        name: "IntelliJ IDEA-EAP", bundleID: "com.jetbrains.intellij-EAP",
        shortVersion: "EAP IU-262.1.1", buildVersion: "IU-262.1.1",
        path: URL(fileURLWithPath: path),
        isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil)
    guard let verdict = await source(tool: tool, at: path).verdict(for: eap) else {
        return  // offline / API hiccup — don't fail the suite
    }
    let url = try #require(verdict.changelogURL)
    #expect(url.host == "youtrack.jetbrains.com")
}

/// Toolbox updated Air itself (262.43.32 → 262.132.21) between two checks. The
/// rescan re-reads the bundle, but the row still carries the verdict from when
/// .32 was installed — "update available, latest 262.132.21" — so the row read
/// "262.132.21 → 262.132.21" until the next network check. Toolbox's own
/// `buildNumber` says the update landed; the row must settle offline.
@Test func toolboxRowSettlesWhenToolboxInstalledTheUpdateItself() {
    let air = airApp(toolboxInstalledBuild: "262.132.21")
    let remote = RemoteVersion(
        shortVersion: "262.132.21", version: "262.132.21", downloadURL: nil,
        sourceName: "Toolbox", requiresManualInstaller: true)
    let settled = UpdateChecker.evaluateToolbox(
        cached: .updateAvailable(latest: "262.132.21"), installed: air, remote: remote)
    #expect(settled == .upToDate)
}

/// The same rescan while the update genuinely hasn't landed must leave the
/// verdict alone — this path never re-decides an update, it only clears one.
@Test func toolboxRowKeepsVerdictWhileInstalledBuildStillBehind() {
    let air = airApp(toolboxInstalledBuild: "262.43.32")
    let remote = RemoteVersion(
        shortVersion: "262.132.21", version: "262.132.21", downloadURL: nil,
        sourceName: "Toolbox", requiresManualInstaller: true)
    let cached = UpdateStatus.updateAvailable(latest: "262.132.21")
    #expect(UpdateChecker.evaluateToolbox(cached: cached, installed: air, remote: remote) == cached)
}

/// A pinned/managed row whose verdict deliberately suppressed a cross-line build
/// reports its own installed build as "latest" — settling it to up-to-date agrees
/// with the verdict. But with no Toolbox build to compare (a tool `state.json`
/// doesn't record), the cached verdict is all we have and must survive.
@Test func toolboxRowWithoutInstalledBuildKeepsVerdict() {
    let air = airApp(toolboxInstalledBuild: nil)
    let remote = RemoteVersion(
        shortVersion: "262.132.21", version: "262.132.21", downloadURL: nil,
        sourceName: "Toolbox", requiresManualInstaller: true)
    let cached = UpdateStatus.updateAvailable(latest: "262.132.21")
    #expect(UpdateChecker.evaluateToolbox(cached: cached, installed: air, remote: remote) == cached)
}

/// Air's on-disk `CFBundleShortVersionString`/`CFBundleVersion` are a divergent
/// runtime track, which is exactly why this path can't use `evaluate` — hold them
/// at values that would mis-compare, so a regression to `evaluate` fails here.
private func airApp(toolboxInstalledBuild: String?) -> InstalledApp {
    InstalledApp(
        name: "Air", bundleID: nil, shortVersion: "262.132", buildVersion: "262.617",
        path: URL(fileURLWithPath: "/Users/x/Applications/Air.app"),
        isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil,
        toolboxInstalledBuild: toolboxInstalledBuild)
}

@Test func displayVersionReducesToNumericCore() {
    #expect(ToolboxInventory.numericVersion(from: "Otter 3 Feature Drop 2025.2.3") == "2025.2.3")
    #expect(ToolboxInventory.numericVersion(from: "Koala Feature Drop 2024.1.2 Patch 1") == "2024.1.2")
    #expect(ToolboxInventory.numericVersion(from: "261.474 Public Preview") == "261.474")
    #expect(ToolboxInventory.numericVersion(from: "2026.1.2") == "2026.1.2")
    // No dotted run → keep the raw string rather than inventing one.
    #expect(ToolboxInventory.numericVersion(from: "Nightly") == "Nightly")
}

/// 2026-09-21, as the endpoints answered that day: Air's Sparkle feed
/// (`fleet-feed/AIR/eap`) offered 262.991.1 while the releases API — and
/// Toolbox's own catalog, and the website's download link — stopped at
/// 262.834.44, which Toolbox had just installed. The row read "262.834.44 →
/// 262.991.1 [Toolbox]" and Toolbox had nothing to give. The API is the answer
/// Toolbox agrees with, so an Air row asks it and is up to date.
@Suite(.serialized)
struct ToolboxAirReleasesAPITests {
    private final class Endpoints: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requested: [URL] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url!
            Self.requested.append(url)
            let body = url.host == "data.services.jetbrains.com"
                ? #"{"AIR":[{"date":"2026-09-16","type":"preview","version":"262.834","build":"262.834.44","notesLink":"https://youtrack.jetbrains.com/issues?q=AIR"}]}"#
                : "<rss><channel><item><sparkle:version>262.991.1</sparkle:version></item></channel></rss>"
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test func airIsCheckedAgainstTheReleasesAPINotItsSparkleFeed() async throws {
        Endpoints.requested = []
        let path = "/Users/x/Applications/Air.app"
        let tool = ToolboxInventory.Tool(
            productCode: nil, channelType: "eap", installedBuild: "262.834.44",
            displayVersion: "262.834", pinnedLine: nil)
        let air = InstalledApp(
            name: "Air", bundleID: "com.jetbrains.air",
            shortVersion: "262.834.44", buildVersion: "262.834.44",
            path: URL(fileURLWithPath: path), isMASApp: false, isToolboxManaged: true,
            sparkleFeedURL: URL(string:
                "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Endpoints.self]
        let source = ToolboxSource(
            inventory: ToolboxInventory(managedPaths: [path], tools: [path: tool]),
            session: URLSession(configuration: configuration))

        let verdict = try #require(await source.verdict(for: air))
        #expect(verdict.hasUpdate == false)
        #expect(verdict.latestBuild == "262.834.44")
        let asked = try #require(Endpoints.requested.first)
        #expect(Endpoints.requested.count == 1)
        #expect(asked.query?.contains("code=AIR") == true)
        // Air's Public Preview is API type "preview"; `type=eap` alone returns `{}`.
        #expect(asked.query?.contains("preview") == true)
    }
}
