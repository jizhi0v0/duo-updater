import Testing
import Foundation
@testable import DuoUpdaterCore

/// A pkg cask that names neither its app nor its bundle id is found through its
/// package's receipt. Shapes from `karabiner-elements` 16.3.0 (2026-11-09): the
/// cask's artifacts are `pkg` and `binary` only, and the receipt
/// `org.pqrs.Karabiner-Elements` lists Karabiner-Elements.app,
/// Karabiner-EventViewer.app and helper apps under
/// `/Library/Application Support/org.pqrs/`.
@Suite struct HomebrewReceiptMatchTests {
    let entry = CaskEntry(
        token: "karabiner-elements", version: "16.4.0",
        url: URL(string: "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v16.4.0/Karabiner-Elements-16.4.0.dmg"),
        autoUpdates: false, installKind: .brew)

    /// A Caskroom holding `karabiner-elements`, recorded as installed at `version`.
    func caskroom(recording version: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("caskroom-\(UUID().uuidString)")
        let casks = root.appendingPathComponent("karabiner-elements/.metadata/\(version)/20261101120000.000/Casks")
        try FileManager.default.createDirectory(at: casks, withIntermediateDirectories: true)
        try Data().write(to: casks.appendingPathComponent("karabiner-elements.json"))
        return root
    }

    func source(caskroom: URL, owned paths: Set<String>) -> HomebrewCaskSource {
        HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: CaskIndex(
                allByAppFilename: [:], allByBundleID: [:], byToken: ["karabiner-elements": entry])),
            inventory: BrewLocalInventory(caskroomPaths: [caskroom.path]),
            ownership: { _ in
                [ThirdPartyCaskSource.Ownership(token: "karabiner-elements", tap: "homebrew/cask", paths: paths)]
            })
    }

    func app(_ path: String, version: String) -> InstalledApp {
        InstalledApp(
            name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            bundleID: "org.pqrs.Karabiner-Elements.Settings", shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// The catalog keeps such a cask under its token, the only key it has.
    @Test func catalogIndexesAPkgCaskByToken() throws {
        let json = #"""
        [{"token": "karabiner-elements", "version": "16.4.0",
          "url": "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v16.4.0/Karabiner-Elements-16.4.0.dmg",
          "artifacts": [{"pkg": ["Karabiner-Elements.pkg"]},
                        {"binary": ["/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"]}]}]
        """#
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: Data(json.utf8))
        #expect(index.allByAppFilename.isEmpty)
        #expect(index.allByBundleID.isEmpty)
        #expect(index.byToken["karabiner-elements"]?.version == "16.4.0")
    }

    @Test func adoptsTheAppTheReceiptListsAtTheRecordedVersion() async throws {
        let root = try caskroom(recording: "16.3.0")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "/Applications/Karabiner-Elements.app"
        let remote = try await source(caskroom: root, owned: [path])
            .latestVersion(for: app(path, version: "16.3.0"))
        #expect(remote?.sourceName == "Homebrew")
        #expect(remote?.sourceIdentifier == "karabiner-elements")
        #expect(remote?.shortVersion == "16.4.0")
    }

    /// A helper the package also wrote, versioned on its own: offering it the
    /// cask's version would be an update no install can reach.
    @Test func leavesAnAppWhoseVersionIsNotTheRecordedOne() async throws {
        let root = try caskroom(recording: "16.3.0")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "/Applications/Karabiner-Helper.app"
        let remote = try await source(caskroom: root, owned: [path])
            .latestVersion(for: app(path, version: "1.2.0"))
        #expect(remote == nil)
    }

    /// A bundle no receipt lists is not the cask's, whatever it is called.
    @Test func leavesAnAppNoReceiptLists() async throws {
        let root = try caskroom(recording: "16.3.0")
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try await source(caskroom: root, owned: ["/Applications/Karabiner-Elements.app"])
            .latestVersion(for: app("/Applications/Other.app", version: "16.3.0"))
        #expect(remote == nil)
    }
}
