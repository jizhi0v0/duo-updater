import Testing
import Foundation
@testable import DuoUpdaterCore

/// Detection of Squirrel/ShipIt-staged self-updates: an app's own updater has
/// downloaded a newer build into `~/Library/Caches/<bundleID>.ShipIt/` but not
/// yet swapped it in. We fabricate that cache layout in a scratch dir and point
/// `staged(for:cachesDirectory:)` at it.
struct SelfUpdaterStagingTests {

    private let bundleID = "com.example.squirrel"

    /// Build a fake `.app` with the given versions in its Info.plist, returning
    /// its URL.
    private func makeApp(at url: URL, short: String, build: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleShortVersionString": short,
            "CFBundleVersion": build,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    /// Write a `<bundleID>.ShipIt/ShipItState.plist` pointing at `target` (the
    /// installed app) and `update` (the staged bundle).
    private func writeShipItState(in caches: URL, target: URL, update: URL) throws {
        let shipIt = caches.appendingPathComponent("\(bundleID).ShipIt")
        try FileManager.default.createDirectory(at: shipIt, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "bundleIdentifier": bundleID,
            "launchAfterInstallation": false,
            "targetBundleURL": target.absoluteString,
            "updateBundleURL": update.absoluteString,
            "useUpdateBundleName": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0)
        try data.write(to: shipIt.appendingPathComponent("ShipItState.plist"))
    }

    private func app(at path: URL, hasSelfUpdater: Bool = true, short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "Squirrel", bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: path, isMASApp: false, sparkleFeedURL: nil, hasSelfUpdater: hasSelfUpdater)
    }

    private func withScratch(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test func detectsNewerStagedBuild() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.9659.4", build: "1.9659.4")
            let stagedDir = caches.appendingPathComponent("\(bundleID).ShipIt/update.xyz")
            let stagedApp = stagedDir.appendingPathComponent("Squirrel.app")
            try makeApp(at: stagedApp, short: "1.10628.0", build: "1.10628.0")
            try writeShipItState(in: caches, target: installed, update: stagedApp)

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, short: "1.9659.4", build: "1.9659.4"),
                cachesDirectory: caches)
            #expect(result?.version == "1.10628.0")
        }
    }

    /// Current Squirrel.Mac writes ShipItState as JSON (despite the `.plist`
    /// extension), which `PropertyListSerialization` can't read — the bug that
    /// made real-world Claude detection silently no-op. Detection must handle it.
    @Test func detectsWhenStateIsJSONNotPlist() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.9659.4", build: "1.9659.4")
            let stagedApp = caches.appendingPathComponent("\(bundleID).ShipIt/update.xyz/Squirrel.app")
            try makeApp(at: stagedApp, short: "1.10628.0", build: "1.10628.0")
            // Write the state as JSON, the way the real updater does.
            let shipIt = caches.appendingPathComponent("\(bundleID).ShipIt")
            let state: [String: Any] = [
                "launchAfterInstallation": false,
                "targetBundleURL": installed.absoluteString,
                "updateBundleURL": stagedApp.absoluteString,
                "bundleIdentifier": bundleID,
            ]
            let data = try JSONSerialization.data(withJSONObject: state)
            try data.write(to: shipIt.appendingPathComponent("ShipItState.plist"))

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, short: "1.9659.4", build: "1.9659.4"),
                cachesDirectory: caches)
            #expect(result?.version == "1.10628.0")
        }
    }

    @Test func ignoresStaleStateAtOrBelowInstalledVersion() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.10628.0", build: "1.10628.0")
            // Staged bundle equals what's installed — already applied, leftover state.
            let stagedApp = caches.appendingPathComponent("\(bundleID).ShipIt/update.xyz/Squirrel.app")
            try makeApp(at: stagedApp, short: "1.10628.0", build: "1.10628.0")
            try writeShipItState(in: caches, target: installed, update: stagedApp)

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, short: "1.10628.0", build: "1.10628.0"),
                cachesDirectory: caches)
            #expect(result == nil)
        }
    }

    @Test func ignoresStateTargetingADifferentBundle() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.0", build: "1.0")
            let otherTarget = root.appendingPathComponent("Other.app")
            try makeApp(at: otherTarget, short: "1.0", build: "1.0")
            let stagedApp = caches.appendingPathComponent("\(bundleID).ShipIt/update.xyz/Squirrel.app")
            try makeApp(at: stagedApp, short: "2.0", build: "2.0")
            // State's target is a *different* app than the one we query.
            try writeShipItState(in: caches, target: otherTarget, update: stagedApp)

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, short: "1.0", build: "1.0"),
                cachesDirectory: caches)
            #expect(result == nil)
        }
    }

    @Test func ignoresAppsWithoutSelfUpdater() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.0", build: "1.0")
            let stagedApp = caches.appendingPathComponent("\(bundleID).ShipIt/update.xyz/Squirrel.app")
            try makeApp(at: stagedApp, short: "2.0", build: "2.0")
            try writeShipItState(in: caches, target: installed, update: stagedApp)

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, hasSelfUpdater: false, short: "1.0", build: "1.0"),
                cachesDirectory: caches)
            #expect(result == nil)
        }
    }

    @Test func returnsNilWhenNoStateFile() throws {
        try withScratch { root in
            let caches = root.appendingPathComponent("Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let installed = root.appendingPathComponent("Squirrel.app")
            try makeApp(at: installed, short: "1.0", build: "1.0")

            let result = SelfUpdaterStaging.staged(
                for: app(at: installed, short: "1.0", build: "1.0"),
                cachesDirectory: caches)
            #expect(result == nil)
        }
    }
}
