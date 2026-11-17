import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct HomebrewCandidateFallbackTests {
    private let owner = CaskEntry(token: "zz-real-owner", version: "2.0", url: nil,
                                   autoUpdates: false, installKind: .brew)
    private let collision = CaskEntry(token: "zz-unrelated", version: "9.0", url: nil,
                                       autoUpdates: false, installKind: .brew)

    private func app(_ path: String, version: String = "1.0") -> InstalledApp {
        InstalledApp(name: "Collision", bundleID: "org.example.real-owner", shortVersion: version, buildVersion: nil,
                     path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    private func caskroom() throws -> URL {
        let root = TestScratch.directory("cask-fallback")
        let record = root.appendingPathComponent("zz-real-owner/.metadata/1.0/20261117120000.000/Casks")
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
        try Data().write(to: record.appendingPathComponent("zz-real-owner.json"))
        return root
    }

    private func source(root: URL, byBundle: [CaskEntry], ownedPath: String,
                        filename: [CaskEntry]? = nil) -> HomebrewCaskSource {
        let index = CaskIndex(
            allByAppFilename: ["collision.app": filename ?? [collision]],
            allByBundleID: ["org.example.real-owner": byBundle],
            byToken: [owner.token: owner, collision.token: collision])
        return HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: index),
            inventory: BrewLocalInventory(caskroomPaths: [root.path]),
            hostOSVersion: "26.1", hostArchitecture: .arm64,
            ownership: { _ in
                [ThirdPartyCaskSource.Ownership(token: "zz-real-owner", tap: "homebrew/cask", paths: [ownedPath])]
            })
    }

    @Test func unrelatedFilenameDoesNotBlockTheBundleIDOwner() async throws {
        let root = try caskroom()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("apps/Collision.app").path
        // Below the record on purpose: a successful bundle-ID match must not
        // inherit the receipt-only helper guard when filename candidates failed.
        let release = try await source(root: root, byBundle: [owner], ownedPath: path)
            .latestVersion(for: app(path, version: "0.5"))
        #expect(release?.sourceIdentifier == owner.token)
        #expect(release?.shortVersion == "2.0")
    }

    @Test func unrelatedFilenameAndBundleIDDoNotBlockTheReceiptOwner() async throws {
        let root = try caskroom()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("apps/Collision.app").path
        let release = try await source(root: root, byBundle: [collision], ownedPath: path)
            .latestVersion(for: app(path))
        #expect(release?.sourceIdentifier == owner.token)
        #expect(release?.shortVersion == "2.0")
    }

    @Test func receiptOnlyHelperStillHasNoUnreachableCaskUpdate() async throws {
        let root = try caskroom()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("apps/Collision.app").path
        let release = try await source(root: root, byBundle: [collision], ownedPath: path)
            .latestVersion(for: app(path, version: "0.5"))
        #expect(release == nil)
    }

    @Test func fallbackNeverAdoptsASameNamedCopyAtAnotherPath() async throws {
        let root = try caskroom()
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appendingPathComponent("owned/Collision.app").path
        let unowned = root.appendingPathComponent("other/Collision.app").path
        let release = try await source(root: root, byBundle: [owner], ownedPath: owned)
            .latestVersion(for: app(unowned))
        #expect(release == nil)
    }
}
