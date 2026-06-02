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
