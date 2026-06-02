import Testing
import Foundation
@testable import DuoUpdaterCore

/// `UpdateResult.isMajorUpgrade` drives the "this may need a new license" badge.
/// The vendor's Sparkle `minimumAutoupdateVersion` is authoritative when present;
/// only when it's absent do we fall back to guessing from the marketing major.
struct MajorUpgradeSignalTests {

    private func app(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "Demo", bundleID: "com.example.demo",
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Demo.app"),
            isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            sparkleEdPublicKey: "key")
    }

    private func remote(short: String, build: String, floor: String?,
                        source: String = "Sparkle") -> RemoteVersion {
        RemoteVersion(
            shortVersion: short, version: build, downloadURL: nil,
            sourceName: source, minimumAutoupdateVersion: floor)
    }

    private func result(installedShort: String, installedBuild: String,
                        newShort: String, newBuild: String, floor: String?,
                        source: String = "Sparkle") -> UpdateResult {
        UpdateResult(
            app: app(short: installedShort, build: installedBuild),
            remote: remote(short: newShort, build: newBuild, floor: floor, source: source),
            status: .updateAvailable(latest: newShort))
    }

    // MARK: - Parser

    @Test func parserReadsMinimumAutoupdateVersion() {
        let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <sparkle:version>200</sparkle:version>
              <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
              <sparkle:minimumAutoupdateVersion>200</sparkle:minimumAutoupdateVersion>
              <enclosure url="https://example.com/2.0.dmg" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(Data(feed.utf8))
        #expect(items.first?.minimumAutoupdateVersion == "200")
    }

    // MARK: - Authoritative vendor signal

    @Test func flagsWhenInstalledSitsBelowVendorFloor() {
        // v1 user, v2 release whose floor is v2 → vendor says "don't auto-install
        // onto a v1 build" — a genuine major/license boundary.
        let r = result(installedShort: "1.9", installedBuild: "190",
                       newShort: "2.0", newBuild: "200", floor: "200")
        #expect(r.isMajorUpgrade)
    }

    @Test func vendorFloorSuppressesFastCadenceFalsePositive() {
        // Postman-shaped: marketing major jumps 11 → 12, but the vendor's floor is
        // low (no paid boundary here), and the installed build clears it. Must NOT
        // flag, even though the leading number grew.
        let r = result(installedShort: "11.85.1", installedBuild: "11851",
                       newShort: "12.13.2", newBuild: "12132", floor: "100")
        #expect(!r.isMajorUpgrade)
    }

    @Test func vendorFloorEqualToInstalledIsNotMajor() {
        // installed build == floor → at-or-above the line → not a major upgrade.
        let r = result(installedShort: "12.0", installedBuild: "1200",
                       newShort: "12.5", newBuild: "1250", floor: "1200")
        #expect(!r.isMajorUpgrade)
    }

    // MARK: - Fallback heuristic (no vendor signal)

    @Test func fallsBackToMarketingMajorWhenNoFloor() {
        let r = result(installedShort: "6.9", installedBuild: "690",
                       newShort: "7.0", newBuild: "700", floor: nil)
        #expect(r.isMajorUpgrade)
    }

    @Test func fallbackStaysQuietWithinSameMajor() {
        let r = result(installedShort: "7.1", installedBuild: "710",
                       newShort: "7.4", newBuild: "740", floor: nil)
        #expect(!r.isMajorUpgrade)
    }

    @Test func blankFloorIsTreatedAsAbsent() {
        // A whitespace-only element must not be read as a "floor of empty" — fall
        // back to the heuristic, which here sees 1 → 2 and flags.
        let r = result(installedShort: "1.0", installedBuild: "100",
                       newShort: "2.0", newBuild: "200", floor: "  ")
        #expect(r.isMajorUpgrade)
    }

    // MARK: - Tier 2 guards: license-neutral source

    @Test func vendorSourceSuppressesMajorBump() {
        // Postman-shaped: reaches us via the curated "Vendor" probe registry, no
        // Sparkle floor. Major number jumps 11 → 12 but it's a free GA build.
        let r = result(installedShort: "11.85.1", installedBuild: "11851",
                       newShort: "12.13.2", newBuild: "12132", floor: nil, source: "Vendor")
        #expect(!r.isMajorUpgrade)
    }

    @Test func gitHubSourceSuppressesMajorBump() {
        let r = result(installedShort: "3.9", installedBuild: "390",
                       newShort: "4.0", newBuild: "400", floor: nil, source: "GitHub")
        #expect(!r.isMajorUpgrade)
    }

    @Test func homebrewSourceStillWarns() {
        // Casks can wrap paid apps, so Homebrew is NOT license-neutral.
        let r = result(installedShort: "5.9", installedBuild: "590",
                       newShort: "6.0", newBuild: "600", floor: nil, source: "Homebrew")
        #expect(r.isMajorUpgrade)
    }

    @Test func highMajorPaidAppViaSparkleStillWarns() {
        // Parallels/Office-shaped: high major, paid per major, no floor set,
        // ordinary (non-neutral) source. Must keep warning — magnitude alone must
        // never suppress.
        let r = result(installedShort: "25.0", installedBuild: "2500",
                       newShort: "26.0", newBuild: "2600", floor: nil, source: "Sparkle")
        #expect(r.isMajorUpgrade)
    }

    // MARK: - Tier 2 guards: CalVer

    @Test func calVerBumpIsNotMajor() {
        // JetBrains-shaped year-led version: 2024.x → 2025.x is a date rollover.
        let r = result(installedShort: "2024.3", installedBuild: "2024300",
                       newShort: "2025.1", newBuild: "2025100", floor: nil, source: "Sparkle")
        #expect(!r.isMajorUpgrade)
    }

    @Test func calendarVersionDetection() {
        #expect(VersionComparator.isCalendarVersion("2024.1"))
        #expect(VersionComparator.isCalendarVersion("2024.11.5"))
        #expect(VersionComparator.isCalendarVersion("v2025.2"))
        #expect(!VersionComparator.isCalendarVersion("12.13.2"))
        #expect(!VersionComparator.isCalendarVersion("1.2024"))
        #expect(!VersionComparator.isCalendarVersion("26.0"))
    }
}
