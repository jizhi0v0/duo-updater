import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ToolboxInventory` is the truth source for which apps JetBrains Toolbox
/// manages. The fragile part is path matching — two installs can share a bundle
/// id (Android Studio Koala + Otter), so only the resolved path separates them.

@Test func toolboxInventoryMatchesByResolvedPath() {
    let koala = "/Users/x/Applications/Android Studio Koala.app"
    let otter = "/Users/x/Applications/Android Studio.app"
    let inv = ToolboxInventory(managedPaths: [koala, otter])

    #expect(inv.isManaged(appPath: URL(fileURLWithPath: koala)))
    #expect(inv.isManaged(appPath: URL(fileURLWithPath: otter)))
    // A same-named app elsewhere is NOT managed — path, not bundle id, decides.
    #expect(!inv.isManaged(appPath: URL(fileURLWithPath: "/Applications/Android Studio.app")))
}

@Test func toolboxInventoryEmptyWhenStateMissing() {
    let inv = ToolboxInventory(stateURL: URL(fileURLWithPath: "/nonexistent/state.json"))
    #expect(!inv.isManaged(appPath: URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app")))
}

@Test func toolboxInventoryParsesStateJSON() throws {
    let json = """
    {
      "tools": [
        { "displayName": "IntelliJ IDEA",
          "installLocation": "/Users/x/Applications/IntelliJ IDEA.app" },
        { "displayName": "Android Studio",
          "installLocation": "/Users/x/Applications/Android Studio.app" }
      ]
    }
    """
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("toolbox-state-test.json")
    try json.data(using: .utf8)!.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let inv = ToolboxInventory(stateURL: tmp)
    #expect(inv.isManaged(appPath: URL(fileURLWithPath: "/Users/x/Applications/IntelliJ IDEA.app")))
    #expect(inv.isManaged(appPath: URL(fileURLWithPath: "/Users/x/Applications/Android Studio.app")))
    #expect(!inv.isManaged(appPath: URL(fileURLWithPath: "/Users/x/Applications/PyCharm.app")))
}

/// A freshly-added EAP tool has an EMPTY `toolBuilds` array (it records installs,
/// and this channel has only ever installed the build it came with) — it must
/// still resolve to the "eap" channel type from the quality filter. Regression:
/// the empty array used to collapse `channelInfo` to nil, defaulting `channelType`
/// to "release" — which routed the EAP install to the stable API track, reported
/// an older stable build as "latest", and hid the install as up to date.
@Test func emptyBuildCacheStillReadsEAPChannelType() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("toolbox-empty-cache-\(UUID().uuidString)", isDirectory: true)
    let channelsDir = dir.appendingPathComponent("channels", isDirectory: true)
    try FileManager.default.createDirectory(at: channelsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let channelID = "IDEA-U-empty"
    // EAP quality filter (order_value > 10000) but no cached builds yet.
    let channelJSON = """
    { "channel": { "updateFilter": { "quality_filter": { "order_value": 40000 } },
                   "history": { "toolBuilds": [] } } }
    """
    try channelJSON.data(using: .utf8)!.write(to: channelsDir.appendingPathComponent("\(channelID).json"))

    let stateJSON = """
    { "tools": [
        { "displayName": "IntelliJ IDEA", "productCode": "IU",
          "buildNumber": "262.6653.22", "displayVersion": "2026.2 EAP",
          "channelId": "\(channelID)",
          "installLocation": "/Users/x/Applications/IntelliJ IDEA 2026.2 EAP.app" }
    ] }
    """
    try stateJSON.data(using: .utf8)!.write(to: dir.appendingPathComponent("state.json"))

    let inv = ToolboxInventory(stateURL: dir.appendingPathComponent("state.json"))
    let tool = inv.tool(forApp: URL(fileURLWithPath: "/Users/x/Applications/IntelliJ IDEA 2026.2 EAP.app"))
    #expect(tool?.channelType == "eap")
    // The live API is the source of truth for what's newer; all Toolbox owes us
    // here is the build it installed and which track to ask about.
    #expect(tool?.installedBuild == "262.6653.22")
}

/// A Toolbox-managed app must not be probed by vendor/GitHub sources, even when
/// a recipe/rule matches its bundle id — its update channel is Toolbox.
@Test func toolboxManagedAppSkipsVendorProbe() async throws {
    // IntelliJ has a vendor recipe; mark the app Toolbox-managed and the probe
    // must decline (return nil) without any network call.
    let app = InstalledApp(
        name: "IntelliJ IDEA",
        bundleID: "com.jetbrains.intellij",
        shortVersion: "2026.1.2",
        buildVersion: "261.24374.151",
        path: URL(fileURLWithPath: "/Users/x/Applications/IntelliJ IDEA.app"),
        isMASApp: false,
        isToolboxManaged: true,
        sparkleFeedURL: nil
    )
    let result = try await VendorProbeSource().latestVersion(for: app)
    #expect(result == nil)
}

/// And the engine labels such an app as Toolbox-managed, not unknown.
@Test func toolboxManagedAppLabelledManaged() async {
    let app = InstalledApp(
        name: "Android Studio",
        bundleID: "com.google.android.studio",
        shortVersion: "2025.2",
        buildVersion: "252.0",
        path: URL(fileURLWithPath: "/Users/x/Applications/Android Studio.app"),
        isMASApp: false,
        isToolboxManaged: true,
        sparkleFeedURL: nil
    )
    let checker = UpdateChecker(sources: [VendorProbeSource(), GitHubReleasesSource()])
    let result = await checker.check(app)
    #expect(result.status == .toolboxManaged)
}
