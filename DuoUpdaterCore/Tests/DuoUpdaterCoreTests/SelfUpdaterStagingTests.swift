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

    // MARK: - Spotify (its own, non-Squirrel staging layout)

    private let spotifyID = "com.spotify.client"

    /// Write Spotify's `PersistentCache/Update/{update.json,<staged>.tbz}` into an
    /// Application Support scratch dir, returning that dir for the param injection.
    private func writeSpotifyStaging(
        in appSupport: URL, from: String, to: String, tbzExists: Bool = true
    ) throws -> URL {
        let dir = appSupport.appendingPathComponent("Spotify/PersistentCache/Update", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tbz = dir.appendingPathComponent("spotify-autoupdate-\(to).gHASH-26.tbz")
        if tbzExists { try Data([0x42]).write(to: tbz) }
        // Mirror the REAL file faithfully: `installation_id` holds raw non-UTF8
        // bytes, so the file is NOT valid JSON. A naive JSONSerialization parse
        // fails on it — detection must regex the clean fields out instead.
        var data = Data(#"{"installation_id":""#.utf8)
        data.append(contentsOf: [0xCE, 0x91, 0xAD, 0x04, 0x4E])  // invalid UTF-8 sequence
        data.append(Data(#"","version_from":"\#(from)","version_to":"\#(to)","update_path":"\#(tbz.path)"}"#.utf8))
        try data.write(to: dir.appendingPathComponent("update.json"))
        return appSupport
    }

    private func spotifyApp(short: String) -> InstalledApp {
        // Spotify is NOT a Squirrel app — hasSelfUpdater stays false; its branch
        // keys on the bundle id, not that flag.
        InstalledApp(
            name: "Spotify", bundleID: spotifyID, shortVersion: short, buildVersion: nil,
            path: .init(fileURLWithPath: "/Applications/Spotify.app"),
            isMASApp: false, sparkleFeedURL: nil, hasSelfUpdater: false)
    }

    @Test func detectsSpotifyNativeStagedUpdate() throws {
        try withScratch { root in
            let appSupport = try writeSpotifyStaging(
                in: root, from: "1.2.92.147", to: "1.2.92.148")
            // Installed value even carries the trailing .gHASH the About panel shows.
            let result = SelfUpdaterStaging.staged(
                for: spotifyApp(short: "1.2.92.147.g5b8f9367"),
                applicationSupportDirectory: appSupport)
            #expect(result?.version == "1.2.92.148")
        }
    }

    @Test func ignoresSpotifyStagingAtOrBelowInstalled() throws {
        try withScratch { root in
            // update.json left over after the swap already landed: installed == to.
            let appSupport = try writeSpotifyStaging(
                in: root, from: "1.2.92.147", to: "1.2.92.148")
            let result = SelfUpdaterStaging.staged(
                for: spotifyApp(short: "1.2.92.148"),
                applicationSupportDirectory: appSupport)
            #expect(result == nil)
        }
    }

    @Test func ignoresSpotifyStagingWhenArchiveGone() throws {
        try withScratch { root in
            // update.json present but the .tbz was already consumed/cleared.
            let appSupport = try writeSpotifyStaging(
                in: root, from: "1.2.92.147", to: "1.2.92.148", tbzExists: false)
            let result = SelfUpdaterStaging.staged(
                for: spotifyApp(short: "1.2.92.147"),
                applicationSupportDirectory: appSupport)
            #expect(result == nil)
        }
    }

    @Test func mayHaveStagingCoversSquirrelAndSpotifyOnly() {
        #expect(SelfUpdaterStaging.mayHaveStaging(spotifyApp(short: "1.0")))
        #expect(SelfUpdaterStaging.mayHaveStaging(
            app(at: .init(fileURLWithPath: "/X.app"), short: "1.0", build: "1.0")))  // Squirrel
        // A plain non-Squirrel, non-Spotify app is skipped (no filesystem probe).
        let plain = InstalledApp(
            name: "Plain", bundleID: "com.example.plain", shortVersion: "1.0", buildVersion: "1.0",
            path: .init(fileURLWithPath: "/Plain.app"), isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false)
        #expect(!SelfUpdaterStaging.mayHaveStaging(plain))
    }
}
