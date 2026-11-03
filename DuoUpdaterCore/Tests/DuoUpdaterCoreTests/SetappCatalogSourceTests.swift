import Foundation
import Testing

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
            releases: { releases },
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
        #expect(answer.version == "3148")
    }

    @Test func aCatalogFailureDoesNotHandTheRowToTheVendorFeed() async throws {
        let source = SetappCatalogSource(
            releases: { throw URLError(.timedOut) },
            subscription: { nil },
            now: { Date() })
        // Not a throw: a throw lets the checker fall through to Sparkle, which
        // reads the dead vendor feed — the direct-edition offer this source is
        // here to stop.
        let answer = try #require(try await source.latestVersion(for: app()))
        #expect(answer.shortVersion == "1.0")
        #expect(answer.downloadURL == nil)
        #expect(answer.sourceName == "Setapp")
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
            releases: { releases },
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
        let answer = try #require(try await source.latestVersion(for: installed))
        #expect(answer.shortVersion == "3.14.7")
        #expect(answer.subscriptionHold == nil)
    }

    @Test func rejectsAPayloadThatIsNotTheCatalogue() {
        #expect(throws: (any Error).self) {
            try SetappCatalog.parse(Data("{\"nope\":true}".utf8))
        }
    }

    // MARK: - Source

    @Test func ignoresAppsThatAreNotSetappEditions() async throws {
        let source = SetappCatalogSource(
            releases: { Self.releases }, subscription: { nil }, now: { .init() })
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
            releases: { Self.releases },
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
            releases: { Self.releases },
            subscription: {
                self.state(expires: "2099-01-01 00:00:00 +0000", grace: "2099-01-15 00:00:00 +0000")
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let answer = try #require(try await source.latestVersion(for: app()))
        #expect(answer.shortVersion == "1.3.0")
        #expect(answer.version == "130")
        #expect(answer.downloadURL == nil)
        #expect(answer.pageURL == URL(string: "setapp://install?app_id=AAAA-1111"))
        #expect(answer.sourceName == "Setapp")
        #expect(answer.subscriptionHold == nil)
    }

    @Test func withholdsTheVersionOnceTheSubscriptionHasLapsed() async throws {
        let source = SetappCatalogSource(
            releases: { Self.releases },
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
            releases: { [:] },
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
