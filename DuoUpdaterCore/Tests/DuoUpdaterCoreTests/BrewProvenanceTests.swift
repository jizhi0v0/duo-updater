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
        allByAppFilename: [appFilename.lowercased(): [entry]],
        allByBundleID: [:]
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
        autoUpdates: true, installKind: .brew
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
        autoUpdates: false, installKind: .brew
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

// MARK: - Packaging revision the bundle never carries (#1553)

/// Homebrew's installed version is the newest `.metadata/<version>/<timestamp>`
/// that holds the caskfile — a leftover version dir, an older timestamp or a
/// timestamp without `Casks/<token>.*` does not count.
@Test func inventoryReadsTheVersionHomebrewRecordsAsInstalled() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("caskroom-\(UUID().uuidString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    func record(_ token: String, _ version: String, _ stamp: String, caskfile: String?) throws {
        let dir = tmp.appendingPathComponent("\(token)/.metadata/\(version)/\(stamp)/Casks")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let caskfile {
            try Data().write(to: dir.appendingPathComponent("\(token).\(caskfile)"))
        }
    }
    try record("mkvtoolnix-app", "102.0", "20261001120000.000", caskfile: "rb")
    try record("mkvtoolnix-app", "102.0-2", "20261021200000.000", caskfile: "json")
    try record("leftover", "2.0", "20261001120000.000", caskfile: "json")
    try record("leftover", "3.0", "20261002120000.000", caskfile: nil)
    try fm.createDirectory(at: tmp.appendingPathComponent("bare/1.0"), withIntermediateDirectories: true)

    let inv = BrewLocalInventory(caskroomPaths: [tmp.path])
    #expect(inv.installedVersion(caskToken: "mkvtoolnix-app") == "102.0-2")
    #expect(inv.installedVersion(caskToken: "leftover") == nil)
    #expect(inv.installedVersion(caskToken: "bare") == nil)
    #expect(inv.isInstalled(caskToken: "bare"))
}

private func mkvToolNix(caskroomVersion: String?, appVersion: String = "102.0") async throws -> RemoteVersion? {
    let entry = CaskEntry(
        token: "mkvtoolnix-app", version: "102.0-2",
        url: URL(string: "https://mkvtoolnix.download/macos/releases/102.0/MKVToolNix-102.0-2-arm64.dmg"),
        autoUpdates: false, installKind: .brew
    )
    let source = HomebrewCaskSource(
        catalog: catalog(with: entry, appFilename: "MKVToolNix.app"),
        inventory: BrewLocalInventory(
            installedTokens: ["mkvtoolnix-app"],
            installedVersions: caskroomVersion.map { ["mkvtoolnix-app": $0] } ?? [:])
    )
    // What the 102.0-2 package's Info.plist actually says (read off the real dmg).
    let app = InstalledApp(
        name: "MKVToolNix", bundleID: "download.mkvtoolnix.MKVToolNix",
        shortVersion: appVersion, buildVersion: appVersion,
        path: URL(fileURLWithPath: "/Applications/MKVToolNix.app"),
        isMASApp: false, sparkleFeedURL: nil
    )
    return try await source.latestVersion(for: app)
}

/// Before brew has the revision, it is an update, as in `brew outdated`.
@Test(arguments: ["102.0", "102.0-1", nil] as [String?])
func revisionNotYetInstalledIsStillOffered(caskroomVersion: String?) async throws {
    let remote = try await mkvToolNix(caskroomVersion: caskroomVersion)
    #expect(remote?.shortVersion == "102.0-2")
    #expect(VersionComparator.isNewer(remote?.shortVersion ?? "", than: "102.0"))
}

/// Once brew records "102.0-2" installed, the bundle's 102.0 is that release —
/// the row must not keep offering what was just installed.
@Test func revisionHomebrewRecordsInstalledIsNotOfferedAgain() async throws {
    let remote = try await mkvToolNix(caskroomVersion: "102.0-2")
    #expect(remote?.shortVersion == "102.0")
    #expect(!VersionComparator.isNewer(remote?.shortVersion ?? "", than: "102.0"))
}

/// The revision is dropped only when the rest of it is the bundle's version: a
/// copy brew's record does not describe keeps the cask version as is.
@Test func revisionIsKeptWhenTheBundleIsSomeOtherVersion() async throws {
    let remote = try await mkvToolNix(caskroomVersion: "102.0-2", appVersion: "101.0")
    #expect(remote?.shortVersion == "102.0-2")
}

// MARK: - SourceStack order

/// A brew-installed app that also carries a `SUFeedURL` must be answered by
/// Homebrew, so Homebrew has to be asked before Sparkle. The other way round,
/// Sparkle swaps the bundle in place, the Caskroom keeps the old version, and
/// the next `brew upgrade` reinstalls the release the user already has —
/// reproduced on 2026-09-24 with the `mos` cask (4.2.0 → 4.2.1 by Sparkle, then
/// `brew upgrade` replaced the 4.2.1 bundle with 4.2.1). Read from the
/// production stack rather than restated, so reordering it fails here.
///
/// Only the casks Homebrew actually keeps up to date move: `auto_updates` casks
/// (`homebrewSourceDefersAutoUpdatingCask`) and apps brew did not install
/// (`homebrewSourceSkipsAppNotInCaskroom`) still decline and fall through to
/// Sparkle as before.
@Test func homebrewIsAskedBeforeSparkle() {
    let names = SourceStack.make(githubToken: nil).map(\.name)
    let homebrew = names.firstIndex(of: "Homebrew")
    let sparkle = names.firstIndex(of: "Sparkle")
    #expect(homebrew != nil && sparkle != nil, "stack: \(names)")
    if let homebrew, let sparkle { #expect(homebrew < sparkle, "stack: \(names)") }
}
