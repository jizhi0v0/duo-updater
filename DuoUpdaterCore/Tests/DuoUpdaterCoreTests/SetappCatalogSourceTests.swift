import Foundation
import Testing
import os
import SQLite3

@testable import DuoUpdaterCore

/// The public catalogue, the subscription state beside it, and the source that
/// joins them. The values here are the real shapes measured on 2026-11-03 (see
/// `SetappCatalog`'s doc comment), trimmed to what these tests need.
struct SetappCatalogSourceTests {

    // MARK: - Fixtures

    private static let catalogueJSON = """
    {"data":{"relationships":{"vendors":{"data":[
      {"relationships":{"applications":{"data":[
        {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA-1111","slugs":[{"slug":"thing","primary":true}]},
         "relationships":{"versions":{"data":[
           {"attributes":{"marketing_version":"1.2.0","build_number":"120","release_date":1700000000,"min_os_version":"12.0"}},
           {"attributes":{"marketing_version":"1.3.0","build_number":"130","release_date":1700100000,"min_os_version":"13.0"}}
         ]}}},
        {"attributes":{"bundle_id":"com.example.direct","name":"Direct","public_id":"BBBB-2222","slugs":[{"slug":"direct","primary":true}]},
         "relationships":{"versions":{"data":[
           {"attributes":{"marketing_version":"9.9.9","build_number":"999","release_date":1700200000}}
         ]}}}
      ]}}}
    ]}}}}
    """

    private static let releases: [String: SetappRelease] = (try? SetappCatalog.parse(
        Data(catalogueJSON.utf8))) ?? [:]

    private func app(
        id: String = "com.example.thing-setapp", short: String = "1.0", build: String = "100"
    ) -> InstalledApp {
        InstalledApp(
            name: "Thing", bundleID: id,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Setapp/Thing.app"),
            isMASApp: false,
            sparkleFeedURL: nil)
    }

    private func state(expires: String, grace: String) -> SetappSubscription.State {
        SetappSubscription.State(
            rawState: "paid",
            expiresAt: SetappSubscription.parseDate(expires),
            graceEndsAt: SetappSubscription.parseDate(grace),
            startedAt: nil)
    }

    // MARK: - Parsing

    @Test func parsesEveryCatalogueEntryAtTheNewestRelease() throws {
        let releases = try SetappCatalog.parse(Data(Self.catalogueJSON.utf8))
        // Every id is indexed, suffixed or not: the catalogue IS the set of
        // editions Setapp ships, and matching must not hinge on the convention.
        #expect(releases.count == 2)
        let thing = try #require(releases["com.example.thing-setapp"])
        #expect(thing.shortVersion == "1.3.0")
        #expect(thing.build == "130")
        #expect(thing.minimumSystemVersion == "13.0")
        #expect(thing.publicID == "AAAA-1111")
        #expect(thing.pageURL == URL(string: "https://setapp.com/apps/thing"))
        #expect(releases["com.example.direct"]?.shortVersion == "9.9.9")
        #expect(thing.versions.count == 2)
    }

    @Test func picksTheNewestReleaseThisMacCanRun() throws {
        // The catalogue keeps an older branch alive for older macOS: the newest
        // row may need a system this Mac does not run (Permute ships 4.1 for
        // macOS 26 beside 3.14.8 for 11+).
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.permute-setapp","name":"Permute","public_id":"CCCC-3333","slugs":[{"slug":"permute","primary":true}]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"4.1","build_number":"410","release_date":1700200000,"min_os_version":"26.0"}},
               {"attributes":{"marketing_version":"3.14.8","build_number":"3148","release_date":1700100000,"min_os_version":"11.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let release = try #require(try SetappCatalog.parse(Data(json.utf8))["com.example.permute-setapp"])
        #expect(release.newestCompatible(osVersion: "15.0")?.shortVersion == "3.14.8")
        #expect(release.newestCompatible(osVersion: "27.0")?.shortVersion == "4.1")
        #expect(release.newestCompatible(osVersion: "10.0") == nil)
    }

    @Test func ranksByVersionNotPublicationDate() throws {
        // A maintenance release on an older branch published AFTER the newer
        // major must not shadow it for a Mac that can run both.
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.9.1","build_number":"191","release_date":1700300000,"min_os_version":"11.0"}},
               {"attributes":{"marketing_version":"2.1","build_number":"210","release_date":1700100000,"min_os_version":"11.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let release = try #require(try SetappCatalog.parse(Data(json.utf8))["com.example.thing-setapp"])
        #expect(release.newestCompatible(osVersion: "15.0")?.shortVersion == "2.1")
    }

    @Test func aCopyAheadOfTheStableCatalogueIsNotADowngrade() async throws {
        // A beta left installed after the switch went off: the stable catalogue is
        // behind it, and answering with that release drew "7.1.0 ↓ 6.6.2".
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.surteesstudios.Bartender-setapp","name":"Bartender","public_id":"BBBB","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"6.6.2","build_number":"662000","release_date":1700300000,"min_os_version":"14.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let releases = try SetappCatalog.parse(Data(json.utf8))
        let source = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { false },
            installedIsBeta: { _ in false })
        let installed = InstalledApp(
            name: "Bartender", bundleID: "com.surteesstudios.Bartender-setapp",
            shortVersion: "7.1.0", buildVersion: "700013",
            path: URL(fileURLWithPath: "/Applications/Setapp/Bartender 7 Setapp.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let answer = try #require(try await source.latestVersion(for: installed))
        #expect(answer.shortVersion == "7.1.0")
        // The installed build, not the catalogue's 662000.
        #expect(answer.version == "700013")
        // No beta record available: the one thing we can prove.
        #expect(answer.installedDisplayVersion == "7.1.0 (ahead of Setapp’s stable releases)")
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([installed]).first)
        #expect(result.status == .upToDate)
    }

    @Test func aMissingBuildIsNotABetaMatch() async throws {
        // Same marketing version as a beta, but the installed bundle states no
        // build: nothing proves this copy is that beta.
        let beta = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.4.0","build_number":"140","release_date":1700300000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let source = SetappCatalogSource(
            releases: { _ in beta },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { true },
            installedIsBeta: { _ in false })
        // Built directly: the shared fixture always states a build, and the
        // absence of one is exactly this test's subject.
        let installed = InstalledApp(
            name: "Thing", bundleID: "com.example.thing-setapp",
            shortVersion: "1.4.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Setapp/Thing.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([installed]).first)
        #expect(result.status == UpdateStatus.upToDate)
        #expect(result.remote?.installedDisplayVersion == nil)
    }

    @Test func anInstalledBetaIsStillNamedAfterTheSwitchGoesOff() async throws {
        // The client's database forgets its beta rows on the next stable refresh;
        // the public beta catalogue does not. A copy installed from beta must keep
        // its name after the switch is turned back off.
        let stable = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"6.6.2","build_number":"662000","release_date":1700300000,"min_os_version":"11.0","beta":false}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let beta = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"6.6.2","build_number":"662000","release_date":1700300000,"min_os_version":"11.0","beta":false}},
               {"attributes":{"marketing_version":"7.1.0","build_number":"700013","release_date":1700200000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let source = SetappCatalogSource(
            releases: { channel in channel == .beta ? beta : stable },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { false },
            installedIsBeta: { _ in false })
        let installed = app(short: "7.1.0", build: "700013")
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([installed]).first)
        #expect(result.status == UpdateStatus.upToDate)
        #expect(result.remote?.releaseChannel == .beta)
        #expect(result.remote?.installedDisplayVersion == nil)
    }

    @Test func anAheadCopyWithBetaOnNamesTheBetaChannel() async throws {
        // Ahead of even the beta catalogue: not an error, and not a downgrade —
        // name the channel it is ahead of.
        let beta = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.3.0","build_number":"130","release_date":1700300000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let source = SetappCatalogSource(
            releases: { _ in beta },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { true },
            installedIsBeta: { _ in false })
        let ahead = app(short: "1.5.0", build: "150")
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([ahead]).first)
        #expect(result.status == .upToDate)
        #expect(result.remote?.installedDisplayVersion == "1.5.0 (ahead of Setapp’s beta releases)")
    }

    @Test func anInstalledBetaIsNamedFromTheCatalogue() async throws {
        // Installed copy IS the catalogue's beta: say so without the client's
        // database, and without calling it merely "up to date".
        let beta = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.4.0","build_number":"140","release_date":1700300000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let source = SetappCatalogSource(
            releases: { _ in beta },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { true },
            installedIsBeta: { _ in false })
        let installed = app(short: "1.4.0", build: "140")
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([installed]).first)
        #expect(result.status == .upToDate)
        // A channel, not a parenthetical suffix: the row's existing ChannelTag
        // draws BETA beside the name.
        #expect(result.remote?.releaseChannel == .beta)
        #expect(result.remote?.installedDisplayVersion == nil)
        #expect(result.remote?.minimumSystemVersion == "11.0")
    }
    @Test func parsesTheBetaFlag() throws {
        let release = try #require(try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.3.0","build_number":"130","release_date":1700300000,"min_os_version":"11.0","beta":false}},
               {"attributes":{"marketing_version":"1.4.0","build_number":"140","release_date":1700200000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))["com.example.thing-setapp"])
        #expect(release.versions.first { $0.shortVersion == "1.3.0" }?.isBeta == false)
        #expect(release.versions.first { $0.shortVersion == "1.4.0" }?.isBeta == true)
    }
    @Test func aBetaRecordedByTheClientNamesTheChannel() async throws {
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.surteesstudios.Bartender-setapp","name":"Bartender","public_id":"BBBB","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"6.6.2","build_number":"662000","release_date":1700300000,"min_os_version":"14.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let releases = try SetappCatalog.parse(Data(json.utf8))
        let source = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { false },
            installedIsBeta: { _ in true })
        let installed = InstalledApp(
            name: "Bartender", bundleID: "com.surteesstudios.Bartender-setapp",
            shortVersion: "7.1.0", buildVersion: "700013",
            path: URL(fileURLWithPath: "/Applications/Setapp/Bartender.app"),
            isMASApp: false, sparkleFeedURL: nil)
        // Beta switch off + catalogue behind: Setapp is not offering betas, and
        // the client's catalogue records this build as one — name it.
        let answer = try #require(try await source.latestVersion(for: installed))
        #expect(answer.releaseChannel == .beta)
        #expect(answer.installedDisplayVersion == nil)
    }

    @Test func readsBetaRowsFromTheClientsCatalogue() throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalogue-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }
        var handle: OpaquePointer?
        #expect(sqlite3_open(db.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = """
            CREATE TABLE ZAPP (Z_PK INTEGER PRIMARY KEY, ZBUNDLEIDENTIFIER VARCHAR);
            CREATE TABLE ZAPPVERSION (Z_PK INTEGER PRIMARY KEY, ZAPP INTEGER, ZISBETA INTEGER,
                                      ZMARKETINGVERSION VARCHAR, ZBUILDNUMBER VARCHAR);
            INSERT INTO ZAPP VALUES (1, 'com.example.thing-setapp');
            INSERT INTO ZAPPVERSION VALUES (1, 1, 1, '7.1.0', '700013');
            INSERT INTO ZAPPVERSION VALUES (2, 1, 0, '6.6.2', '662000');
            """
        #expect(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)

        #expect(SetappBetaChannel.installedCopyIsBeta(
            bundleID: "com.example.thing-setapp", shortVersion: "7.1.0",
            build: "700013", database: db))
        // A stable row is not a beta…
        #expect(!SetappBetaChannel.installedCopyIsBeta(
            bundleID: "com.example.thing-setapp", shortVersion: "6.6.2",
            build: "662000", database: db))
        // …and an exact build is required.
        #expect(!SetappBetaChannel.installedCopyIsBeta(
            bundleID: "com.example.thing-setapp", shortVersion: "7.1.0",
            build: "700014", database: db))
        // A missing catalogue answers no rather than throwing.
        #expect(!SetappBetaChannel.installedCopyIsBeta(
            bundleID: "com.example.thing-setapp", shortVersion: "7.1.0",
            build: "700013", database: URL(fileURLWithPath: "/nonexistent/Apps.sqlite")))
    }

    @Test func aSetappEditionUsesTheBaseAppsReleaseNotes() {
        // Setapp ships its own id; the vendor's release notes are keyed by the
        // base one. Without the fallback the notes pane was empty.
        let edition = InstalledApp(
            name: "Moshi", bundleID: "app.getmoshi.desktop-setapp",
            shortVersion: "0.5.13", buildVersion: "0.5.13",
            path: URL(fileURLWithPath: "/Applications/Setapp/Moshi.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let result = UpdateResult(app: edition, remote: nil, status: .upToDate)
        let recipe = ChangelogRecipeSelection.recipe(for: result)
        #expect(recipe?.bundleID == "app.getmoshi.desktop")
    }

    @Test func aBuildOnlyReleaseIsStillAnUpdate() async throws {
        // Same marketing version, newer build: the build must survive, otherwise
        // the checker's marketing fallback calls it current.
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.3.0","build_number":"131","release_date":1700300000,"min_os_version":"11.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let releases = try SetappCatalog.parse(Data(json.utf8))
        let source = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() })
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([app(short: "1.3.0", build: "130")]).first)
        guard case .updateAvailable = result.status else {
            Issue.record("expected a build-only update, got \(result.status)")
            return
        }
        #expect(result.remote?.version == "131")
    }

    @Test func aPublicKeyOwnedCopyNeverFallsThroughToTheVendorFeed() async throws {
        // No `-setapp` suffix, not in the catalogue: only the framework's public
        // key says this is Setapp's. The answer must still be "as installed" —
        // nil would hand the row to Sparkle's direct-edition offer.
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("thing-\(UUID().uuidString).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        FileManager.default.createFile(
            atPath: bundle.appendingPathComponent("Contents/Resources/setappPublicKey.pem").path,
            contents: Data("key".utf8))

        let owned = InstalledApp(
            name: "Thing", bundleID: "com.example.thing",
            shortVersion: "1.0", buildVersion: "100",
            path: bundle, isMASApp: false, sparkleFeedURL: nil)
        let spy = SparkleSpy()
        let source = SetappCatalogSource(
            releases: { _ in [:] }, subscription: { nil }, now: { Date() })
        let checker = UpdateChecker(sources: [source, spy])
        let result = try #require(await checker.check([owned]).first)
        #expect(spy.calls == 0)
        #expect(result.remote?.shortVersion == "1.0")
    }

    @Test func aBetaEnabledCheckReadsTheBetaCatalogue() async throws {
        // With Setapp's beta switch on we read /store/api/v8/beta/en, which is the
        // same public catalogue plus `beta: true` rows. A newer beta is an update,
        // not "cannot be checked".
        let stable = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.3.0","build_number":"130","release_date":1700300000,"min_os_version":"11.0","beta":false}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let beta = try SetappCatalog.parse(Data("""
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.thing-setapp","name":"Thing","public_id":"AAAA","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"1.3.0","build_number":"130","release_date":1700300000,"min_os_version":"11.0","beta":false}},
               {"attributes":{"marketing_version":"1.4.0","build_number":"140","release_date":1700200000,"min_os_version":"11.0","beta":true}}
             ]}}}
          ]}}}
        ]}}}}
        """.utf8))
        let source = SetappCatalogSource(
            releases: { channel in channel == .beta ? beta : stable },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            betaUpdatesEnabled: { true },
            installedIsBeta: { _ in false })
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([app(short: "1.3.0", build: "130")]).first)
        guard case .updateAvailable(let latest) = result.status else {
            Issue.record("expected the beta to be offered, got \(result.status)")
            return
        }
        #expect(latest == "1.4.0")
        #expect(result.remote?.releaseChannel == .beta)
    }

    @Test func offersTheNewestReleaseThatRunsHereNotTheNewestStanding() async throws {
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.permute-setapp","name":"Permute","public_id":"CCCC-3333","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"4.1","build_number":"410","release_date":1700200000,"min_os_version":"26.0"}},
               {"attributes":{"marketing_version":"3.14.8","build_number":"3148","release_date":1700100000,"min_os_version":"11.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let releases = try SetappCatalog.parse(Data(json.utf8))
        let source = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            osVersion: { "15.0" })
        let installed = InstalledApp(
            name: "Permute", bundleID: "com.example.permute-setapp",
            shortVersion: "3.14.7", buildVersion: "3147",
            path: URL(fileURLWithPath: "/Applications/Setapp/Permute.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let answer = try #require(try await source.latestVersion(for: installed))
        #expect(answer.shortVersion == "3.14.8")
        #expect(answer.version == nil)

        // And on a Mac that can run the major, the checker must see it: build 410
        // is numerically below 3148, so a stated build would have suppressed it.
        let modern = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            osVersion: { "27.0" })
        let checker = UpdateChecker(sources: [modern, SparkleSpy()])
        let major = InstalledApp(
            name: "Permute", bundleID: "com.example.permute-setapp",
            shortVersion: "3.14.8", buildVersion: "3148",
            path: URL(fileURLWithPath: "/Applications/Setapp/Permute.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let result = try #require(await checker.check([major]).first)
        guard case .updateAvailable(let latest) = result.status else {
            Issue.record("expected the 4.1 major to be offered, got \(result.status)")
            return
        }
        #expect(latest == "4.1")
    }

    @Test func aCatalogueFailureIsATerminalRetryableCheckFailure() async throws {
        let source = SetappCatalogSource(
            releases: { _ in throw URLError(.timedOut) },
            subscription: { nil },
            now: { Date() })
        let spy = SparkleSpy()
        let checker = UpdateChecker(sources: [source, spy])
        let results = await checker.check([app()])

        // Sparkle reads the dead vendor feed and would offer the direct edition.
        #expect(spy.calls == 0)
        let result = try #require(results.first)
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
        // A timeout is retryable, so CheckFailureRules keeps the row in the retry
        // path instead of treating it as a settled "up to date".
        #expect(result.failureIsTransient)
    }

    @Test func noReleaseThatRunsHereIsStillAnAnswer() async throws {
        let json = """
        {"data":{"relationships":{"vendors":{"data":[
          {"relationships":{"applications":{"data":[
            {"attributes":{"bundle_id":"com.example.permute-setapp","name":"Permute","public_id":"CCCC-3333","slugs":[]},
             "relationships":{"versions":{"data":[
               {"attributes":{"marketing_version":"4.1","build_number":"410","release_date":1700200000,"min_os_version":"26.0"}}
             ]}}}
          ]}}}
        ]}}}}
        """
        let releases = try SetappCatalog.parse(Data(json.utf8))
        let source = SetappCatalogSource(
            releases: { _ in releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date() },
            osVersion: { "15.0" })
        let installed = InstalledApp(
            name: "Permute", bundleID: "com.example.permute-setapp",
            shortVersion: "3.14.7", buildVersion: "3147",
            path: URL(fileURLWithPath: "/Applications/Setapp/Permute.app"),
            isMASApp: false, sparkleFeedURL: nil)
        await #expect(throws: OSWindowRefused.self) {
            _ = try await source.latestVersion(for: installed)
        }

        // The checker reports it as a refused macOS floor, not a checkmark.
        let checker = UpdateChecker(sources: [source, SparkleSpy()])
        let result = try #require(await checker.check([installed]).first)
        guard case .outsideOSWindow = result.status else {
            Issue.record("expected .outsideOSWindow, got \(result.status)")
            return
        }
    }

    @Test func rejectsAPayloadThatIsNotTheCatalogue() {
        #expect(throws: (any Error).self) {
            try SetappCatalog.parse(Data("{\"nope\":true}".utf8))
        }
    }

    // MARK: - Source

    @Test func ignoresAppsThatAreNotSetappEditions() async throws {
        let source = SetappCatalogSource(
            releases: { _ in Self.releases }, subscription: { nil }, now: { .init() })
        // No `-setapp`, not in a Setapp folder, no public key: none of the three
        // signals says this copy is Setapp's, so the source stays out of the way.
        let plain = InstalledApp(
            name: "Direct", bundleID: "com.example.direct",
            shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Direct.app"),
            isMASApp: false, sparkleFeedURL: nil)
        #expect(try await source.latestVersion(for: plain) == nil)
    }

    @Test func answersACatalogueEntryThatBreaksTheNamingConvention() async throws {
        let source = SetappCatalogSource(
            releases: { _ in Self.releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        // Same id as the plain copy above, but installed where Setapp puts its
        // apps: the catalogue is the authority, and it lists this id.
        let inSetappFolder = InstalledApp(
            name: "Direct", bundleID: "com.example.direct",
            shortVersion: "1.0", buildVersion: "100",
            path: URL(fileURLWithPath: "/Applications/Setapp/Direct.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let answer = try #require(try await source.latestVersion(for: inSetappFolder))
        #expect(answer.shortVersion == "9.9.9")
        #expect(answer.sourceName == "Setapp")
    }

    @Test func offersTheCatalogueReleaseWhenTheSubscriptionIsActive() async throws {
        let source = SetappCatalogSource(
            releases: { _ in Self.releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let answer = try #require(try await source.latestVersion(for: app()))
        #expect(answer.shortVersion == "1.3.0")
        // No build is stated: Setapp numbers builds per branch, and the checker
        // prefers builds when both sides have one (see `offer`).
        #expect(answer.version == nil)
        #expect(answer.downloadURL == nil)
        #expect(answer.pageURL == URL(string: "setapp://install?app_id=AAAA-1111"))
        #expect(answer.sourceName == "Setapp")
        #expect(answer.subscriptionHold == nil)
    }

    @Test func withholdsTheVersionOnceTheSubscriptionHasLapsed() async throws {
        let source = SetappCatalogSource(
            releases: { _ in Self.releases },
            subscription: {
                self.state(expires: "2027-01-30 23:59:59 +0000", grace: "2027-02-13 23:59:59 +0000")
            },
            now: { Date(timeIntervalSince1970: 1_804_000_000) })  // 2027-03-01, past the grace too

        let answer = try #require(try await source.latestVersion(for: app()))
        // An answer, not nil: the row keeps its identity and shows the hold.
        #expect(answer.shortVersion == "1.0")
        #expect(answer.subscriptionHold?.version == "1.3.0")
        #expect(answer.subscriptionHold?.coveredBefore == SetappSubscription.parseDate("2027-01-30 23:59:59 +0000"))
    }

    @Test func stillAnsweredAsInstalledWhenTheCatalogueDoesNotListIt() async throws {
        let source = SetappCatalogSource(
            releases: { _ in [:] },
            subscription: { nil },
            now: { Date() })
        // Never nil for a `-setapp` copy: nil would hand the row to the vendor's
        // Sparkle feed, which is the mismatch this source exists to stop.
        let answer = try #require(try await source.latestVersion(for: app(id: "com.example.gone-setapp")))
        #expect(answer.shortVersion == "1.0")
        #expect(answer.pageURL == nil)
        #expect(answer.subscriptionHold == nil)
    }

    // MARK: - Affordance

    @Test func theSetappDeepLinkIsHandedToTheSetappClient() {
        let link = try! #require(URL(string: "setapp://install?app_id=AAAA-1111"))
        let client = URL(fileURLWithPath: "/Applications/Setapp.app")
        #expect(DetectionOnlyAffordance.resolve(pageURL: link, setappClient: client)
            == .openDeepLink(link))
        // No client: do not pretend. Revealing the copy is the honest offer.
        #expect(DetectionOnlyAffordance.resolve(pageURL: link, setappClient: nil) == .revealInFinder)
        // Every other custom scheme still belongs to the app on the row.
        let chrome = try! #require(URL(string: "chrome://settings/help"))
        #expect(DetectionOnlyAffordance.resolve(pageURL: chrome, setappClient: nil) == .openInApp(chrome))
        let page = try! #require(URL(string: "https://setapp.com/apps/thing"))
        #expect(DetectionOnlyAffordance.resolve(pageURL: page, setappClient: nil) == .openPage(page))
    }

    // MARK: - Background updates

    @Test func onlyActionableSetappOffersTriggerBackgroundUpdates() {
        let stable = RemoteVersion(
            shortVersion: "1.2", version: nil, downloadURL: nil, sourceName: "Setapp")
        let beta = RemoteVersion(
            shortVersion: "1.3b1", version: nil, downloadURL: nil, sourceName: "Setapp", releaseChannel: .beta)
        for remote in [stable, beta] {
            #expect(SetappAutomation.hasAvailableUpdate(in: [UpdateResult(
                app: app(), remote: remote, status: .updateAvailable(latest: "1.2"))]))
            #expect(!SetappAutomation.hasAvailableUpdate(in: [UpdateResult(
                app: app(), remote: remote, status: .upToDate)]))
            #expect(!SetappAutomation.hasAvailableUpdate(in: [UpdateResult(
                app: app(), remote: remote, status: .error("offline"))]))
        }
        let direct = RemoteVersion(shortVersion: "2", version: nil, downloadURL: nil, sourceName: "Sparkle")
        #expect(!SetappAutomation.hasAvailableUpdate(in: [UpdateResult(
            app: app(), remote: direct, status: .updateAvailable(latest: "2"))]))
        let held = RemoteVersion(
            shortVersion: "1.2", version: nil, downloadURL: nil, sourceName: "Setapp",
            subscriptionHold: SubscriptionHold(version: "2", coveredBefore: nil, recovery: .setappAccount))
        #expect(!SetappAutomation.hasAvailableUpdate(in: [UpdateResult(
            app: app(), remote: held, status: .upToDate)]))
        #expect(!SetappAutomation.hasAvailableUpdate(in: []))
    }

    /// A Setapp cold launch refreshes the whole catalogue, so an actionable
    /// row must not make a second row's explicitly skipped version collateral.
    @Test func oneSkippedOfferVetoesTheGlobalAutomaticLaunch() {
        let remote = RemoteVersion(
            shortVersion: "1.2", version: nil, downloadURL: nil, sourceName: "Setapp")
        let actionable = UpdateResult(
            app: app(id: "com.example.actionable-setapp"), remote: remote,
            status: .updateAvailable(latest: "1.2"))
        let skipped = UpdateResult(
            app: app(id: "com.example.skipped-setapp"), remote: remote,
            status: .updateAvailable(latest: "1.2"))

        let blocked = SetappAutomation.automaticUpdateCandidates(
            in: [actionable, skipped],
            isVersionSkipped: { $0.app.bundleID == "com.example.skipped-setapp" })
        #expect(blocked.isEmpty)
        #expect(SetappAutomation.automaticUpdateCandidates(
            in: [skipped, actionable],
            isVersionSkipped: { $0.app.bundleID == "com.example.skipped-setapp" }).isEmpty)
        #expect(SetappAutomation.automaticUpdateCandidates(
            in: [skipped], isVersionSkipped: { _ in true }).isEmpty)
        #expect(SetappAutomation.automaticUpdateCandidates(
            in: [], isVersionSkipped: { _ in false }).isEmpty)

        let allowed = SetappAutomation.automaticUpdateCandidates(
            in: [actionable, skipped], isVersionSkipped: { _ in false })
        #expect(allowed.count == 2)
    }

    @Test func anIgnoredSetappCopyWithAStoredSkipVetoesTheGlobalLaunch() {
        let remote = RemoteVersion(
            shortVersion: "1.2", version: nil, downloadURL: nil, sourceName: "Setapp")
        let actionable = UpdateResult(
            app: app(id: "com.example.actionable-setapp"), remote: remote,
            status: .updateAvailable(latest: "1.2"))
        let ignored = app(id: "com.example.ignored-setapp")

        #expect(SetappAutomation.automaticUpdateCandidates(
            in: [actionable],
            ignoredApps: [ignored],
            hasStoredSkip: { $0.bundleID == "com.example.ignored-setapp" },
            isVersionSkipped: { _ in false }).isEmpty)

        // A skipped ignored copy from another distribution cannot be collateral
        // in Setapp's global refresh and must not suppress Setapp updates.
        let direct = app(id: "com.example.direct")
        #expect(SetappAutomation.automaticUpdateCandidates(
            in: [actionable],
            ignoredApps: [direct],
            hasStoredSkip: { _ in true },
            isVersionSkipped: { _ in false }).count == 1)
    }

    @Test func aSkippedDirectOfferDoesNotVetoSetappUpdates() {
        let setapp = UpdateResult(app: app(), remote: RemoteVersion(
            shortVersion: "2.0", version: "200", downloadURL: nil, sourceName: "Setapp"),
            status: .updateAvailable(latest: "2.0"))
        let direct = UpdateResult(app: app(id: "com.example.direct"), remote: RemoteVersion(
            shortVersion: "2.0", version: "200", downloadURL: nil, sourceName: "Sparkle"),
            status: .updateAvailable(latest: "2.0"))
        let updates = SetappAutomation.automaticUpdateCandidates(in: [direct, setapp]) {
            $0.remote?.sourceName == "Sparkle"
        }
        #expect(updates.count == 1)
        #expect(updates.first?.remote?.sourceName == "Setapp")
    }

    @Test func readsSetappsPerCustomerAutoInstallFlag() {
        let suite = "setapp-auto-\(UUID().uuidString)"
        let defaults = try! #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Absent means Setapp's "Install automatically" is on.
        #expect(!SetappAutomation.isAutoRefreshForbidden(defaults: defaults))
        #expect(SetappAutomation.canUpdateInBackground(userEnabled: true, defaults: defaults))

        // The prefix is the account's hash, so the key is matched by suffix.
        defaults.set(1, forKey: "4766321432293575660-ForbiddenAutomaticAppsRefresh")
        #expect(SetappAutomation.isAutoRefreshForbidden(defaults: defaults))
        #expect(!SetappAutomation.canUpdateInBackground(userEnabled: true, defaults: defaults))
        // The user's own switch still wins over Setapp's.
        #expect(!SetappAutomation.canUpdateInBackground(userEnabled: false, defaults: nil))
    }

    @Test func aRunningClientTakesThePageRoute() {
        let suite = "setapp-route-\(UUID().uuidString)"
        let defaults = try! #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Background only when the user allows it, the client is not running and
        // Setapp would install what its launch check finds.
        #expect(SetappAutomation.routesThroughBackground(
            userEnabled: true, clientRunning: false, defaults: defaults))
        #expect(!SetappAutomation.routesThroughBackground(
            userEnabled: true, clientRunning: true, defaults: defaults))
        #expect(!SetappAutomation.routesThroughBackground(
            userEnabled: false, clientRunning: false, defaults: defaults))

        defaults.set(1, forKey: "4766321432293575660-ForbiddenAutomaticAppsRefresh")
        #expect(!SetappAutomation.routesThroughBackground(
            userEnabled: true, clientRunning: false, defaults: defaults))
    }

    // MARK: - Subscription

    @Test func readsTheTrialDatesTheClientWrites() throws {
        let state = try #require(SetappSubscription.state(from: [[
            "subscriptionState": "trial",
            "subscriptionStartDate": "2026-11-03 08:42:25 +0000",
            "subscriptionExpirationDate": "2026-11-09 23:59:59 +0000",
            "gracePeriodExpirationDate": "2026-11-14 23:59:59 +0000",
        ]]))
        let expiry = try #require(state.expiresAt)
        #expect(state.rawState == "trial")
        #expect(state.isActive(now: expiry.addingTimeInterval(-1)))
        // Grace keeps it covering until its own end.
        #expect(state.isActive(now: expiry.addingTimeInterval(60 * 60)))
        #expect(!state.isActive(now: state.graceEndsAt!.addingTimeInterval(1)))
    }

    @Test func readsTheDateFormTheCurrentClientWrites() throws {
        // 3.58.0 stores these as NSDate, not strings: `plutil -p` shows
        // `2026-11-09 23:59:59 +0000` unquoted, while `defaults read` quotes it —
        // which is how an earlier parser read only strings and called a live
        // trial expired.
        let expiry = try #require(SetappSubscription.parseDate("2026-11-09 23:59:59 +0000"))
        let grace = try #require(SetappSubscription.parseDate("2026-11-14 23:59:59 +0000"))
        let state = try #require(SetappSubscription.state(from: [[
            "subscriptionState": "trial",
            "subscriptionExpirationDate": expiry,
            "gracePeriodExpirationDate": grace,
        ]]))
        #expect(state.expiresAt == expiry)
        #expect(state.isActive(now: Date(timeIntervalSince1970: 1_793_000_000)))
    }

    @Test func noReadableCustomerMeansNoState() {
        #expect(SetappSubscription.state(from: []) == nil)
        #expect(SetappSubscription.state(from: [["subscriptionState": "paid"]]) == nil)
    }
}


/// A source that would answer if it were asked. The point of the Setapp tests is
/// that the checker never asks it.
private final class SparkleSpy: UpdateSource, @unchecked Sendable {
    let name = "Sparkle"
    var answersAppStoreCopies: Bool { false }

    private let counter = OSAllocatedUnfairLock(initialState: 0)
    var calls: Int { counter.withLock { $0 } }

    func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        counter.withLock { $0 += 1 }
        return RemoteVersion(
            shortVersion: "9.9.9", version: "999",
            downloadURL: URL(string: "https://example.com/direct.dmg"),
            sourceName: name)
    }
}
