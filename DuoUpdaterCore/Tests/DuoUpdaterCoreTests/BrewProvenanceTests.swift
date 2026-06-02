import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - BrewLocalInventory

@Test func inventoryReadsCaskroomDirectoryNames() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("caskroom-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    for token in ["ghostty", "postman", ".DS_Store"] {
        try fm.createDirectory(at: tmp.appendingPathComponent(token), withIntermediateDirectories: true)
    }

    let inv = BrewLocalInventory(caskroomPaths: [tmp.path])
    #expect(inv.isInstalled(caskToken: "ghostty"))
    #expect(inv.isInstalled(caskToken: "Ghostty"))      // case-insensitive
    #expect(inv.isInstalled(caskToken: "postman"))
    #expect(!inv.isInstalled(caskToken: ".DS_Store"))   // dotfiles ignored
    #expect(!inv.isInstalled(caskToken: "chatwise"))    // not installed
}

@Test func inventoryToleratesMissingCaskroom() {
    let inv = BrewLocalInventory(caskroomPaths: ["/no/such/path"])
    #expect(!inv.isInstalled(caskToken: "anything"))
}

// MARK: - HomebrewCaskSource provenance gate

/// An app whose filename matches a real cask but that Homebrew did NOT install
/// must not be adopted by the Homebrew source — it falls through to "unknown".
@Test func homebrewSourceSkipsAppNotInCaskroom() async throws {
    let source = HomebrewCaskSource(inventory: BrewLocalInventory(installedTokens: []))
    let app = InstalledApp(
        name: "Visual Studio Code", bundleID: "com.microsoft.VSCode",
        shortVersion: "1.119.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
        isMASApp: false, sparkleFeedURL: nil
    )
    // Even if "visual-studio-code" exists in the catalog, with an empty Caskroom
    // the source must decline (return nil).
    let remote = try await source.latestVersion(for: app)
    #expect(remote == nil)
}

// MARK: - HomebrewCaskSource auto_updates gate

private func catalog(with entry: CaskEntry, appFilename: String) -> HomebrewCaskCatalog {
    HomebrewCaskCatalog(testIndex: CaskIndex(
        byAppFilename: [appFilename.lowercased(): entry],
        byBundleID: [:]
    ))
}

private func appNamed(_ filename: String) -> InstalledApp {
    InstalledApp(
        name: filename.replacingOccurrences(of: ".app", with: ""),
        bundleID: "com.example.\(filename)", shortVersion: "1.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/\(filename)"),
        isMASApp: false, sparkleFeedURL: nil
    )
}

/// A brew-installed cask flagged `auto_updates` must NOT be offered a brew
/// upgrade: the app self-updates (brew lags it), and `brew install --cask --force`
/// would re-adopt an app that updates itself. The source defers (nil) → the app
/// falls through to its real channel / "unknown", never a Homebrew row. This is
/// the Postman case: vendor-installed, self-updating, wrongly adopted once.
@Test func homebrewSourceDefersAutoUpdatingCask() async throws {
    let entry = CaskEntry(
        token: "postman", version: "12.12.6",
        url: URL(string: "https://dl.pstmn.io/download/version/12.12.6/osx_arm64"),
        autoUpdates: true, isPkg: false
    )
    let source = HomebrewCaskSource(
        catalog: catalog(with: entry, appFilename: "Postman.app"),
        inventory: BrewLocalInventory(installedTokens: ["postman"])
    )
    let remote = try await source.latestVersion(for: appNamed("Postman.app"))
    #expect(remote == nil)   // self-updating → not classified as Homebrew
}

/// Control: an installed cask that is NOT auto_updates still resolves to a
/// Homebrew-managed update — proving the gate above is specific to self-updaters,
/// not a blanket opt-out.
@Test func homebrewSourceResolvesManagedCask() async throws {
    let entry = CaskEntry(
        token: "tableplus", version: "7.1.0",
        url: URL(string: "https://example.com/TablePlus.dmg"),
        autoUpdates: false, isPkg: false
    )
    let source = HomebrewCaskSource(
        catalog: catalog(with: entry, appFilename: "TablePlus.app"),
        inventory: BrewLocalInventory(installedTokens: ["tableplus"])
    )
    let remote = try await source.latestVersion(for: appNamed("TablePlus.app"))
    #expect(remote?.sourceName == "Homebrew")
    #expect(remote?.shortVersion == "7.1.0")
    #expect(remote?.sourceIdentifier == "tableplus")
}
