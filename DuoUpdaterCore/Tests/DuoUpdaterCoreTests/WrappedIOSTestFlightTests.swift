import Testing
import Foundation
import SQLite3
@testable import DuoUpdaterCore

/// A TestFlight-installed iPhone/iPad app running on Apple Silicon must be
/// recognized as a TestFlight install, not as an App Store copy (#456).
///
/// Why it needed its own signals: the receipt environment `readApp` prefers is
/// unavailable for a wrapped bundle. Measured 2026-09-08 on all three iOS-on-Mac
/// apps on one machine — two from TestFlight, one bought from the store —
/// `kMDItemAppStoreReceiptType` was null on every one and no `_MASReceipt`
/// existed anywhere in any of the bundles. And the TestFlight database files a
/// wrapped app's rows under `ZPLATFORMRAW` 1, which the mac-only query never
/// selected: `com.ampcode.amp.ios` sat there at build 64 — matching the
/// installed build exactly — and was invisible.
///
/// The consequence was not cosmetic. `isMAS` falls out of `!isTestFlight &&
/// (isiOSAppOnMac || hasReceipt)`, so a TestFlight-only app read as a store copy
/// and `MacAppStoreSource` probed it against a listing that does not exist:
/// measured, seven fallback storefronts per scan, every scan, each answering a
/// 42-byte `resultCount: 0` — 1248 requests in 15 hours for one app.
///
/// Every case names the mutation it catches. All eleven were run against this
/// commit's parent-plus-fix and every one turned the file red on the case that
/// names it — including the two that only a wrong answer in the *other*
/// direction can trigger (`aStoreBoughtWrappedAppIsStillAStoreCopy` needs
/// `wrappedBundleIsTestFlight` to return true unconditionally;
/// `aWrappedBundleWithNoMetadataFallsBackToTodaysAnswer` needs an unreadable
/// plist to fall back to true).
///
/// Some mutations redden more than the one case, because several fixtures are
/// legitimately wrapped bundles and a broken wrapped-bundle signal fails all of
/// them. That is collateral, not coverage: what each case is *for* is the
/// mutation named in its own doc comment.
struct WrappedIOSTestFlightTests {

    // MARK: - Fixtures

    /// Plants a wrapped iPhone/iPad bundle: `WrappedBundle` symlink, inner
    /// `Wrapper/<name>.app/Info.plist`, and optionally the store metadata that
    /// sits beside it.
    ///
    /// `metadata` is written as the real installs write it — the top-level key,
    /// the nested one, or both — so a case can name exactly which key it is
    /// testing rather than relying on a fixture that happens to carry both.
    private static func plantWrapped(
        bundleID: String,
        build: String = "64",
        metadata: [String: Any]?,
        in root: URL
    ) throws -> URL {
        let fm = FileManager.default
        let bundle = root.appendingPathComponent("Fixture.app")
        let inner = bundle.appendingPathComponent("Wrapper/Inner.app")
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleDisplayName": "Fixture",
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": build,
        ]
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: inner.appendingPathComponent("Info.plist"))
        try fm.createSymbolicLink(
            atPath: bundle.appendingPathComponent("WrappedBundle").path,
            withDestinationPath: "Wrapper/Inner.app")
        if let metadata {
            try PropertyListSerialization
                .data(fromPropertyList: metadata, format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Wrapper/iTunesMetadata.plist"))
        }
        return bundle
    }

    /// A normal Mac bundle, for the cases that pin what must NOT change.
    private static func plantNative(
        bundleID: String, build: String = "1138", in root: URL
    ) throws -> URL {
        let fm = FileManager.default
        let bundle = root.appendingPathComponent("Native.app")
        let contents = bundle.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleDisplayName": "Native",
                "CFBundleIdentifier": bundleID,
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": build,
            ] as [String: Any],
            format: .xml, options: 0
        ).write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

    /// What the store-bought wrapped app carried: no beta keys at all, and the
    /// catalog metadata a TestFlight build has no way to acquire. A function
    /// rather than a stored property because `[String: Any]` is not `Sendable`.
    private static func storeMetadata() -> [String: Any] {
        [
            "softwareVersionBundleId": "com.example.app.ios",
            "softwareVersionExternalIdentifier": 876543210,
            "releaseDate": "2026-08-01T00:00:00Z",
            "rating": ["name": "4+"],
            "storefrontCountryCode": "us",
        ]
    }

    /// A scanner that cannot reach the real TestFlight database.
    ///
    /// `AppScanner()` defaults `testflight:` to `TestFlightInventory()`, which
    /// opens the developer's own TestFlight container — so a bare `AppScanner()`
    /// here would make these cases depend on machine state (a real row for the
    /// fixture's bundle id would flip the store-copy case) and pay the app-data
    /// privacy gate, which this code's own comments record blocking for ten
    /// minutes. Every case below asserts the plist signal, so the inventory is
    /// empty on purpose: whatever they prove, they prove about the plist.
    private static func plistOnlyScanner() -> AppScanner {
        AppScanner(testflight: TestFlightInventory(macRows: []))
    }

    private static func withTemporaryRoot<T>(_ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrapped-tf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    // MARK: - The plist signal

    /// Mutation: drop the `betaExternalVersionIdentifier` branch from
    /// `wrappedBundleIsTestFlight`.
    ///
    /// The fixture carries ONLY that key, so a reader that has quietly come to
    /// depend on the nested one cannot pass. It also asserts `isiOSAppOnMac`
    /// first: a fixture that stopped reading as wrapped would make the real
    /// assertion vacuous, since `isMASApp` would then be false for the wrong
    /// reason (no receipt) rather than the right one.
    @Test func theTopLevelBetaKeyAloneIsEnough() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios",
                metadata: ["betaExternalVersionIdentifier": 234431759], in: root)
            let app = try #require(Self.plistOnlyScanner().scan(bundlesAt: [bundle]).first)
            #expect(app.isiOSAppOnMac, "fixture stopped reading as a wrapped bundle")
            #expect(app.isTestFlightApp)
            #expect(!app.isMASApp)
        }
    }

    /// Mutation: drop the `distributorInfo` branch.
    ///
    /// Only the nested key is present. Both branches exist so that a rename of
    /// one does not take the signal with it, and neither is load-bearing alone —
    /// which is only true if each is separately exercised.
    @Test func theNestedBetaTesterTypeAloneIsEnough() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios",
                metadata: ["distributorInfo": ["betaTesterType": 2]], in: root)
            let app = try #require(Self.plistOnlyScanner().scan(bundlesAt: [bundle]).first)
            #expect(app.isiOSAppOnMac, "fixture stopped reading as a wrapped bundle")
            #expect(app.isTestFlightApp)
            #expect(!app.isMASApp)
        }
    }

    /// Mutation: compare `betaTesterType` against a value (`== 2`) instead of
    /// testing for presence.
    ///
    /// What that `2` means is undocumented, so nothing may branch on it. A tester
    /// type this code has never seen must still read as a beta.
    @Test func anUnseenBetaTesterTypeStillReadsAsABeta() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios",
                metadata: ["distributorInfo": ["betaTesterType": 99]], in: root)
            let app = try #require(Self.plistOnlyScanner().scan(bundlesAt: [bundle]).first)
            #expect(app.isTestFlightApp)
        }
    }

    /// Mutation: return `true` when the plist is missing or unparseable.
    ///
    /// The store-bought wrapped app is the one that must keep going to
    /// `MacAppStoreSource` — it has a real listing there — so over-tagging is a
    /// regression in the opposite direction, and it would be silent: the row
    /// would simply stop checking for updates.
    @Test func aStoreBoughtWrappedAppIsStillAStoreCopy() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios", metadata: Self.storeMetadata(), in: root)
            let app = try #require(Self.plistOnlyScanner().scan(bundlesAt: [bundle]).first)
            #expect(app.isiOSAppOnMac, "fixture stopped reading as a wrapped bundle")
            #expect(!app.isTestFlightApp)
            #expect(app.isMASApp)
        }
    }

    /// Mutation: make an unreadable plist fall back to `true`.
    ///
    /// A wrapped bundle with no metadata at all must land on exactly today's
    /// behaviour — store copy — rather than on a guess. This is the direction the
    /// fix is allowed to fail in.
    @Test func aWrappedBundleWithNoMetadataFallsBackToTodaysAnswer() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios", metadata: nil, in: root)
            let app = try #require(Self.plistOnlyScanner().scan(bundlesAt: [bundle]).first)
            #expect(app.isiOSAppOnMac, "fixture stopped reading as a wrapped bundle")
            #expect(!app.isTestFlightApp)
            #expect(app.isMASApp)
        }
    }

    // MARK: - The database signal

    /// Mutation: delete the `isiOSAppOnMac && testflight.hasInstalledIOSBuild(…)` clause
    /// from `readApp`.
    ///
    /// The plist is absent here, so the DB row is the only thing that can carry
    /// this — the two signals are asserted separately on purpose, because a
    /// fixture holding both would let either one rot unnoticed.
    @Test func aniOSPlatformRowAloneIdentifiesAWrappedTestFlightApp() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios", build: "64", metadata: nil, in: root)
            let scanner = AppScanner(testflight: TestFlightInventory(
                macRows: [],
                iosRows: [(bundleID: "com.example.app.ios", shortVersion: "1.0", build: "64")]))
            let app = try #require(scanner.scan(bundlesAt: [bundle]).first)
            #expect(app.isiOSAppOnMac, "fixture stopped reading as a wrapped bundle")
            #expect(app.isTestFlightApp)
            #expect(!app.isMASApp)
        }
    }

    /// Mutation: relax the build match in `hasInstalledIOSBuild` to a bundle-id match.
    ///
    /// The same reason `isManaged` matches on the build: the user may merely have
    /// TestFlight *access* to an app whose store copy is what is installed here.
    @Test func aniOSRowForADifferentBuildDoesNotTagThisCopy() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios", build: "64", metadata: nil, in: root)
            let scanner = AppScanner(testflight: TestFlightInventory(
                macRows: [],
                iosRows: [(bundleID: "com.example.app.ios", shortVersion: "1.1", build: "77")]))
            let app = try #require(scanner.scan(bundlesAt: [bundle]).first)
            #expect(!app.isTestFlightApp)
            #expect(app.isMASApp)
        }
    }

    /// Mutation: drop the `app.isiOSAppOnMac &&` guard in front of `hasInstalledIOSBuild`
    /// (in `readApp`, and again in `applyingTestFlightInventory`).
    ///
    /// A native Mac app commonly holds iOS rows for betas the user tests on a
    /// phone — both TestFlight Mac apps on the machine this was written on do.
    /// Tagging a Mac bundle off one of those would be tagging it on the strength
    /// of a build installed somewhere else entirely.
    @Test func aNativeMacAppIsNotTaggedByItsPhoneBetas() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantNative(bundleID: "com.example.mac", build: "1138", in: root)
            let inventory = TestFlightInventory(
                macRows: [],
                iosRows: [(bundleID: "com.example.mac", shortVersion: "1.4.0", build: "1138")])
            let app = try #require(AppScanner(testflight: inventory).scan(bundlesAt: [bundle]).first)
            #expect(!app.isiOSAppOnMac, "fixture must be a native bundle for this to mean anything")
            #expect(!app.isTestFlightApp)

            let retagged = AppScanner.applyingTestFlightInventory(inventory, to: [app])[0]
            #expect(!retagged.isTestFlightApp)
        }
    }

    /// Mutation: merge `iosBuildsByBundleID` into `buildsByBundleID` (or feed iOS
    /// rows into `appsByBundleID`).
    ///
    /// Mithka on the machine this was written on carries mac 1138 and iOS 1149 in
    /// the same database. A merged table offers it the phone build as its next
    /// Mac update — a wrong version, not a missing one, and `latest` is what
    /// `UpdateChecker` turns into the offer.
    @Test func iOSRowsNeverBecomeTheLatestMacBuild() {
        let inventory = TestFlightInventory(
            macRows: [(bundleID: "ad.neko.mithka", shortVersion: "1.4.0", build: "1138")],
            iosRows: [(bundleID: "ad.neko.mithka", shortVersion: "1.4.0", build: "1149")])
        #expect(inventory.latest(forBundleID: "ad.neko.mithka")?.latestBuild == "1138")
        // And the mac-only membership question keeps its old answer, so nothing
        // that was already right starts depending on the new bucket.
        #expect(inventory.isManaged(bundleID: "ad.neko.mithka", installedBuild: "1138"))
        #expect(!inventory.isManaged(bundleID: "ad.neko.mithka", installedBuild: "1149"))
        #expect(inventory.hasInstalledIOSBuild(bundleID: "ad.neko.mithka", installedBuild: "1149"))
    }

    /// Mutation: apply the new iOS clause in `applyingTestFlightInventory`
    /// unconditionally, or not at all.
    ///
    /// This is the pass that runs once the app-data privacy gate is finally
    /// answered — the first scan deliberately runs with an empty inventory — so a
    /// wrapped app whose plist has been reshaped by a future OS is corrected
    /// here or nowhere.
    @Test func theLateInventoryPassAlsoCorrectsAWrappedApp() throws {
        try Self.withTemporaryRoot { root in
            let bundle = try Self.plantWrapped(
                bundleID: "com.example.app.ios", build: "64", metadata: nil, in: root)
            let blind = AppScanner(testflight: TestFlightInventory(macRows: [], accessible: false))
            let before = try #require(blind.scan(bundlesAt: [bundle]).first)
            #expect(!before.isTestFlightApp, "fixture must start untagged for this to mean anything")
            #expect(before.isMASApp)

            let after = AppScanner.applyingTestFlightInventory(
                TestFlightInventory(
                    macRows: [],
                    iosRows: [(bundleID: "com.example.app.ios", shortVersion: "1.0", build: "64")]),
                to: [before])[0]
            #expect(after.isTestFlightApp)
            #expect(!after.isMASApp)
        }
    }

    // MARK: - What the SQL itself decides

    /// The two buckets are filled in `openAndRead`, which only runs against a real
    /// database file — the `macRows:`/`iosRows:` seam takes rows that are already
    /// sorted, so nothing reaching it can prove the query is right. These cases
    /// build an actual SQLite file instead.
    private static func plantDatabase(
        _ rows: [(bundleID: String, short: String, build: String, platform: Int32, installed: Int32)],
        in root: URL
    ) throws -> URL {
        let url = root.appendingPathComponent("TestFlight.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, """
            CREATE TABLE ZTFAPPBUNDLEMODEL (
              ZBUNDLEID TEXT, ZSHORTVERSION TEXT, ZBUNDLEVERSION TEXT,
              ZPLATFORMRAW INTEGER, ZINSTALLSTATUSRAW INTEGER);
            """, nil, nil, nil) == SQLITE_OK)
        for row in rows {
            let sql = """
                INSERT INTO ZTFAPPBUNDLEMODEL VALUES \
                ('\(row.bundleID)', '\(row.short)', '\(row.build)', \(row.platform), \(row.installed));
                """
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        return url
    }

    /// Mutation: drop the `where sqlite3_column_int64(stmt, 4) == Self.installedHere`
    /// guard on the iOS bucket.
    ///
    /// This is the whole reason the DB clause cannot promote a store copy of an app
    /// the user merely beta-tests. Mithka on the machine this was written on is the
    /// real shape: an iOS row it has ACCESS to (build 1149, not installed here) next
    /// to the Mac row that IS installed. Only the installed one may answer.
    @Test func onlyTheIOSBuildTestFlightSaysIsInstalledHereCounts() throws {
        try Self.withTemporaryRoot { root in
            let db = try Self.plantDatabase([
                (bundleID: "com.example.app.ios", short: "1.0", build: "64",
                 platform: 1, installed: 1),
                (bundleID: "com.example.app.ios", short: "1.1", build: "77",
                 platform: 1, installed: 0),
            ], in: root)
            let inventory = TestFlightInventory(databaseURL: db)
            #expect(inventory.accessible, "fixture database was not opened")
            #expect(inventory.hasInstalledIOSBuild(
                bundleID: "com.example.app.ios", installedBuild: "64"))
            #expect(!inventory.hasInstalledIOSBuild(
                bundleID: "com.example.app.ios", installedBuild: "77"))
        }
    }

    /// Mutation: apply the same install filter to the macOS bucket.
    ///
    /// It must NOT be applied there. `latest(forBundleID:)` is asking which builds
    /// are *available*; keeping only the installed one would make every TestFlight
    /// Mac app permanently up to date — a silent stop to updates, with every row
    /// still rendering normally.
    @Test func macRowsKeepTheBuildsThatAreMerelyAvailable() throws {
        try Self.withTemporaryRoot { root in
            let db = try Self.plantDatabase([
                (bundleID: "com.example.mac", short: "1.0", build: "100",
                 platform: 3, installed: 1),
                (bundleID: "com.example.mac", short: "1.1", build: "200",
                 platform: 3, installed: 0),
            ], in: root)
            let inventory = TestFlightInventory(databaseURL: db)
            #expect(inventory.latest(forBundleID: "com.example.mac")?.latestBuild == "200")
            #expect(inventory.isManaged(bundleID: "com.example.mac", installedBuild: "100"))
        }
    }

    /// Mutation: restore the `else { iosRows.append(…) }` bucketing.
    ///
    /// A platform the query does not name must reach neither bucket. Written as an
    /// `else`, a later widening of the `IN` list would file unidentified rows as
    /// iOS evidence with nothing red; matched positively, it is a no-op.
    @Test func anUnknownPlatformReachesNeitherBucket() throws {
        try Self.withTemporaryRoot { root in
            let db = try Self.plantDatabase([
                (bundleID: "com.example.other", short: "1.0", build: "300",
                 platform: 2, installed: 1),
                (bundleID: "com.example.other", short: "1.0", build: "400",
                 platform: 4, installed: 1),
            ], in: root)
            let inventory = TestFlightInventory(databaseURL: db)
            #expect(inventory.accessible, "fixture database was not opened")
            #expect(!inventory.hasInstalledIOSBuild(
                bundleID: "com.example.other", installedBuild: "300"))
            #expect(!inventory.hasInstalledIOSBuild(
                bundleID: "com.example.other", installedBuild: "400"))
            #expect(inventory.latest(forBundleID: "com.example.other") == nil)
        }
    }
}
