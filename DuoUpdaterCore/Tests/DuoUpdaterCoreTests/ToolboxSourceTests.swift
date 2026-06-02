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

@Test func pinnedToolSuppressesCrossLineUpdate() async {
    let path = "/Users/x/Applications/Android Studio.app"
    // Kept on the 2025.2.3 line (build branch 252); the local cache offers a
    // 2025.3 build (branch 253) — that crosses the pin and must be suppressed.
    let tool = ToolboxInventory.Tool(
        productCode: "AI", channelType: "release", installedBuild: "252.28238.7",
        localLatestVersion: "2025.3.4", localLatestBuild: "253.5",
        isNewestOfProduct: false,  // → uses Toolbox's local cache, no network
        displayVersion: "2025.2.3", pinnedLine: "2025.2.3")
    let verdict = await source(tool: tool, at: path).verdict(for: app(at: path))
    #expect(verdict?.hasUpdate == false)
    // And reports the installed version, not the phantom 2025.3.4.
    #expect(verdict?.latestVersion == "2025.2.3")
}

@Test func pinnedToolStillSurfacesInLinePatch() async {
    let path = "/Users/x/Applications/Android Studio.app"
    // A same-line patch (252 → 252, newer build) is what the pin allows.
    let tool = ToolboxInventory.Tool(
        productCode: "AI", channelType: "release", installedBuild: "252.28238.7",
        localLatestVersion: "2025.2.4", localLatestBuild: "252.99999.9",
        isNewestOfProduct: false,  // → uses Toolbox's local cache, no network
        displayVersion: "2025.2.3", pinnedLine: "2025.2.3")
    let verdict = await source(tool: tool, at: path).verdict(for: app(at: path))
    #expect(verdict?.hasUpdate == true)
}

@Test func unpinnedToolReportsCrossLineUpdate() async {
    let path = "/Users/x/Applications/Android Studio.app"
    // No pin → the cross-line build is a real update.
    let tool = ToolboxInventory.Tool(
        productCode: "AI", channelType: "release", installedBuild: "252.28238.7",
        localLatestVersion: "2025.3.4", localLatestBuild: "253.5",
        isNewestOfProduct: false,  // → uses Toolbox's local cache, no network
        displayVersion: "2025.2.3", pinnedLine: nil)
    let verdict = await source(tool: tool, at: path).verdict(for: app(at: path))
    #expect(verdict?.hasUpdate == true)
    #expect(verdict?.latestVersion == "2025.3.4")
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
    let path = "/Users/x/Applications/Air.app"
    let tool = ToolboxInventory.Tool(
        productCode: nil, channelType: "eap", installedBuild: "261.617",
        localLatestVersion: "261.474 Public Preview", localLatestBuild: "261.474.25",
        displayVersion: "261.474", pinnedLine: nil)
    let air = InstalledApp(
        name: "Air", bundleID: nil, shortVersion: "261.474", buildVersion: "261.617",
        path: URL(fileURLWithPath: path), isMASApp: false, isToolboxManaged: true,
        sparkleFeedURL: nil)
    let verdict = await source(tool: tool, at: path).verdict(for: air)
    #expect(verdict == nil)
}

@Test func displayVersionReducesToNumericCore() {
    #expect(ToolboxInventory.numericVersion(from: "Otter 3 Feature Drop 2025.2.3") == "2025.2.3")
    #expect(ToolboxInventory.numericVersion(from: "Koala Feature Drop 2024.1.2 Patch 1") == "2024.1.2")
    #expect(ToolboxInventory.numericVersion(from: "261.474 Public Preview") == "261.474")
    #expect(ToolboxInventory.numericVersion(from: "2026.1.2") == "2026.1.2")
    // No dotted run → keep the raw string rather than inventing one.
    #expect(ToolboxInventory.numericVersion(from: "Nightly") == "Nightly")
}
