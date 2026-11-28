import Foundation
import Testing
@testable import DuoUpdaterCore

struct UkeleleRecipeTests {
    @Test func legacySignedCapitalizationMayOnlyUpgradeOnTheOriginalTeam() {
        let old = "org.sil.Ukelele", new = "org.sil.ukelele", team = "3YE4W86L3G"
        #expect(BundleIDMigration.migration(
            installed: old, downloaded: new, installedVersion: "3.4.2",
            installedTeam: team, downloadedTeam: team) != nil)
        #expect(BundleIDMigration.migration(
            installed: new, downloaded: old, installedVersion: "3.4.2",
            installedTeam: team, downloadedTeam: team) == nil)
        #expect(BundleIDMigration.migration(
            installed: old, downloaded: new, installedVersion: "3.4.2",
            installedTeam: team, downloadedTeam: "OTHERTEAM1") == nil)
        #expect(BundleIDMigration.migration(
            installed: old, downloaded: new, installedVersion: "3.5.12",
            installedTeam: team, downloadedTeam: team) == nil)
    }

    @Test func onlyTheOfficialFeedClassifiesUntaggedBetas() throws {
        let bundleID = org_sil_ukelele.bundleID
        let feed = try #require(SparkleFeedCatalog.feed(forBundleID: bundleID))
        let body = Data(Self.appcast.utf8)
        let items = SparkleAppcastSource.parsedItems(body, feedURL: feed, bundleID: bundleID)
        #expect(items.map(\.channel) == [nil, "beta", "beta", "preview"])

        let anotherFeed = try #require(URL(string: "https://example.invalid/update.xml"))
        #expect(SparkleAppcastSource.parsedItems(body, feedURL: anotherFeed, bundleID: bundleID)
            .map(\.channel) == [nil, nil, nil, "preview"])
        #expect(SparkleAppcastSource.parsedItems(body, feedURL: feed, bundleID: "com.example.other")
            .map(\.channel) == [nil, nil, nil, "preview"])

        func installed(_ version: String, _ build: String, _ channel: ReleaseChannel) -> InstalledApp {
            InstalledApp(
                name: "Ukelele", bundleID: bundleID, shortVersion: version, buildVersion: build,
                path: URL(fileURLWithPath: "/Applications/Ukelele.app"), isMASApp: false,
                sparkleFeedURL: feed, releaseChannel: channel, channelIsAuthoritative: false)
        }

        let stable = SparkleAppcastSource.usableItems(
            for: installed("3.5.12", "396", .stable), from: items, osVersion: "26.0.0")
        #expect(stable.map(\.version) == ["475"])

        let beta = SparkleAppcastSource.usableItems(
            for: installed("3.6b7", "450", .beta), from: items, osVersion: "26.0.0")
        #expect(beta.map(\.version) == ["475", "450", "448"])
        #expect(SparkleAppcastSource.offerableItem(for: installed("3.6b7", "450", .beta),
                                                 from: beta)?.version == "475")
    }

    @Test func officialHistorySeparatesReleaseParagraphs() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: org_sil_ukelele.bundleID))
        let input = """
        <h2 id="versions">Versions</h2><h3>4 November 2026 — Released version 3.7.1</h3>
        <p>Fixed a bug that prevented creating a new keyboard collection.</p><h3>19 October 2026 — Released version 3.7</h3>
        <p>Added a way to remove user-defined keyboard types.</p><p>Resolved an issue with keyboard type definitions which misplaced non-rectangular keys.</p><h3>11 March 2026 — Released version 3.6.1</h3>
        <p>Prevent creating a key output longer than 20 UTF-16 code units, which is the limit imposed by Apple.</p></article><p>Website navigation.</p>
        """
        let log = try #require(ChangelogExtractor.extract(from: input, using: recipe))
        #expect(log.entries.map(\.version) == ["3.7.1", "3.7", "3.6.1"])
        #expect(VersionComparator.compare(log.entries[1].version, "3.7.0") == .orderedSame)
        #expect(log.entries[0].date == "4 November 2026")
        #expect(log.entries[0].items == ["Fixed a bug that prevented creating a new keyboard collection."])
        #expect(log.entries[1].items == ["Added a way to remove user-defined keyboard types.",
                                        "Resolved an issue with keyboard type definitions which misplaced non-rectangular keys."])
        #expect(log.entries[2].items == ["Prevent creating a key output longer than 20 UTF-16 code units, which is the limit imposed by Apple."])
    }

    // Trimmed SIL appcast. The last item intentionally adds an explicit channel
    // to pin the vendor-tag precedence when SIL starts publishing tags.
    private static let appcast = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    <item><title>Ukelele 3.7.1</title><enclosure url="Ukelele_3.7.1.dmg" sparkle:version="475" sparkle:shortVersionString="3.7.1"/></item>
    <item><title>Ukelele 3.6b7</title><enclosure url="Ukelele_3.6b7.dmg" sparkle:version="450" sparkle:shortVersionString="3.6b7"/></item>
    <item><title>Ukelele 3.6b6</title><enclosure url="Ukelele_3.6b6.dmg" sparkle:version="448" sparkle:shortVersionString="3.6b6"/></item>
    <item><title>Ukelele 3.6b5</title><sparkle:channel>preview</sparkle:channel><enclosure url="Ukelele_3.6b5.dmg" sparkle:version="442" sparkle:shortVersionString="3.6b5"/></item>
    </channel></rss>
    """
}
