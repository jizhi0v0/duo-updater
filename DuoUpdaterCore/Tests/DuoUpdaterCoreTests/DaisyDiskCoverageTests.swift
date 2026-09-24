import Testing
import Foundation
@testable import DuoUpdaterCore

/// DaisyDisk needs no `VendorProbeRecipe`, `GitHubReleaseRule`, or
/// `ChannelBinding`: its direct-download build ships a genuine `SUFeedURL` that
/// the generic `SparkleAppcastSource` already resolves, so it is fully covered
/// with zero registry entries. The Homebrew cask (`auto_updates: true`) makes
/// `HomebrewCaskSource` decline it (`homebrewSourceDefersAutoUpdatingCask`), so
/// the check falls through to Sparkle, which answers. See
/// `docs/app-audits/com-daisydiskapp-DaisyDiskStandAlone.md` for the full audit;
/// this file exists so a future change to the generic Sparkle pipeline can't
/// silently regress this app back to `.unknown` without a test noticing.
///
/// Feed captured verbatim from
/// `https://daisydiskapp.com/downloads/appcastFeed.php` on 2026-08-29 — the same
/// URL the Homebrew cask's own `livecheck do ... strategy :sparkle` points at.
/// No `<sparkle:channel>` tag anywhere: one stable track, five releases, already
/// newest-first in document order (pubDate descending).
private let daisyDiskFeedFixture = #"""
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><item><title>Version 4.34.2</title><sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://daisydiskapp.com//releases/main/macos/br5</sparkle:releaseNotesLink><pubDate>2026-07-10 12:32:20</pubDate><enclosure url="https://daisydiskapp.com//download/DaisyDisk.zip" sparkle:version="4.34.2" sparkle:shortVersionString="4.34.2" length="7982277" sparkle:dsaSignature="MC0CFQCNWjangc1MmFFQvRPoQ97Sol+vcQIUP1y4h7+XCEbgPeK02NyHKKVIUBo=" type="application/octet-stream"/></item><item><title>Version 4.24</title><sparkle:minimumSystemVersion>10.10</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://daisydiskapp.com//releases/main/macos/br4</sparkle:releaseNotesLink><pubDate>2022-11-03 12:50:21</pubDate><enclosure url="https://daisydiskapp.com//download/DaisyDisk_4_24.zip" sparkle:version="4.24" sparkle:shortVersionString="4.24" length="9854383" sparkle:dsaSignature="MCwCFHC2eq3QsT+RajoDBWche8lXx02oAhR82kmBZOMVFpk3yfDY6y/wkxwwyg==" type="application/octet-stream"/></item><item><title>Version 3.0.3.1</title><sparkle:minimumSystemVersion>10.7</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://daisydiskapp.com//releases/main/macos/br3</sparkle:releaseNotesLink><pubDate>2014-06-20 15:24:00</pubDate><enclosure url="https://daisydiskapp.com//download/DaisyDisk_3_0_3_1.zip" sparkle:version="3.0.3.1" sparkle:shortVersionString="3.0.3.1" length="6955287" sparkle:dsaSignature="MC0CFQCl71z7x9PVQfToLpeCIt8hNpg7/wIUaiUNbLu8HQbJa4vjgxDOxKJmX3M=" type="application/octet-stream"/></item><item><title>Version 2.1.2</title><sparkle:minimumSystemVersion>10.6</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://daisydiskapp.com//releases/main/macos/br2</sparkle:releaseNotesLink><pubDate>2012-06-27 14:40:16</pubDate><enclosure url="https://daisydiskapp.com//download/DaisyDisk_2_1_2.dmg" sparkle:version="2.1.2" sparkle:shortVersionString="2.1.2" length="3940800" sparkle:dsaSignature="MCwCFED1rkMEWs/9sDts3DQuirFYZ8hNAhRa8aCcnvBpW4z4bEAZBOgetSGy9g==" type="application/octet-stream"/></item><item><title>Version 2.0.7.2</title><sparkle:minimumSystemVersion>10.5</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://daisydiskapp.com//releases/main/macos/br1</sparkle:releaseNotesLink><pubDate>2011-07-03 00:00:00</pubDate><enclosure url="https://daisydiskapp.com//download/DaisyDisk_2_0_7_2.dmg" sparkle:version="2.0.7.2" sparkle:shortVersionString="2.0.7.2" length="5008222" sparkle:dsaSignature="MC0CFFYm5EouNWBjFq2zhzs2ud9qLtT8AhUAoFnngJrngmDllRTO3I6rR/We8h8=" type="application/octet-stream"/></item></channel></rss>
"""#

/// Field values match a real bundle downloaded and unzipped from
/// `https://daisydiskapp.com/download/DaisyDisk.zip` on 2026-08-29 and again on
/// 2026-09-14: `CFBundleIdentifier` = `com.daisydiskapp.DaisyDiskStandAlone`,
/// `CFBundleShortVersionString` == `CFBundleVersion` == "4.34.2", no
/// `SUPublicEDKey`, `SUFeedURL` = the exact URL the fixture above was fetched from.
///
/// The path is made up on purpose: nothing here should depend on what this host
/// has installed (CLAUDE.md, 「测试不能问宿主」), so it is asserted absent.
private func daisyDiskApp(shortVersion: String, buildVersion: String) -> InstalledApp {
    let path = "/Applications/ZZFixture-DaisyDisk.app"
    #expect(!FileManager.default.fileExists(atPath: path),
            "fixture path \(path) exists on this host")
    return InstalledApp(
        name: "DaisyDisk", bundleID: "com.daisydiskapp.DaisyDiskStandAlone",
        shortVersion: shortVersion, buildVersion: buildVersion,
        path: URL(fileURLWithPath: path),
        isMASApp: false,
        sparkleFeedURL: URL(string: "https://daisydiskapp.com/downloads/appcastFeed.php"),
        sparkleEdPublicKey: nil)
}

@Suite struct DaisyDiskCoverageTests {
    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(Data(daisyDiskFeedFixture.utf8))
    }

    @Test func genericSparklePicksTheNewestRealRelease() {
        let app = daisyDiskApp(shortVersion: "4.34", buildVersion: "4.34")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "15.0")
        #expect(best?.shortVersionString == "4.34.2")
        #expect(best?.version == "4.34.2")
        #expect(best?.enclosureURL?.absoluteString == "https://daisydiskapp.com//download/DaisyDisk.zip")
    }

    @Test func upToDateInstallMatchesTheTopOfFeedExactly() {
        let app = daisyDiskApp(shortVersion: "4.34.2", buildVersion: "4.34.2")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "15.0")
        let installed = VersionSide(marketing: app.shortVersion, build: app.buildVersion)
        let remote = VersionSide(marketing: best?.shortVersionString, build: best?.version)
        #expect(VersionComparator.isSame(installed, as: remote))
        #expect(VersionComparator.isNewer(remote, than: installed) == false)
    }

    /// The whole reason no `ChannelBinding` entry is needed: nothing in the real
    /// feed tags a channel, so every item lands on the default (stable) track
    /// `SparkleAppcastSource.usableItems` already allows without help.
    @Test func realFeedCarriesNoChannelTags() {
        #expect(items.allSatisfy { $0.channel == nil })
    }

    @Test func oldReleasesStillParseForTheChangelogHistory() {
        let app = daisyDiskApp(shortVersion: "4.34.2", buildVersion: "4.34.2")
        let usable = SparkleAppcastSource.usableItems(for: app, from: items, osVersion: "15.0")
        #expect(usable.map { $0.shortVersionString } == ["4.34.2", "4.24", "3.0.3.1", "2.1.2", "2.0.7.2"])
    }
}
