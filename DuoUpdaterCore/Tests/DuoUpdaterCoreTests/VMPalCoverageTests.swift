import Testing
import Foundation
@testable import DuoUpdaterCore

/// VMPal ships Sparkle without an `SUFeedURL`, so the generic
/// `SparkleAppcastSource` only reaches it through the `SparkleFeedCatalog` entry
/// in `Recipes/com-tableplus-VMPal.swift`. See
/// `docs/app-audits/com-tableplus-VMPal.md` for the audit.
///
/// Feed captured verbatim from `https://vmpal.com/apps/version.xml` on
/// 2026-10-06. Note the shape: the root carries `sparkle="…"` as a plain
/// attribute, the Sparkle namespace is declared on `<enclosure>` alone, and
/// `<minimumSystemVersion>` is unprefixed.
private let vmPalFeedFixture = #"""
<rss sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item><enclosure xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" sparkle:version="36" sparkle:shortVersionString="0.36" length="42262248" type="application/octet-stream" sparkle:dsaSignature="" sparkle:edSignature="j5P+zj4B6dQsMMGJ3jEKOHU36iyVO8pIiVI20Xgi3m14pvlCkpErksAhDm2FMi+llVdPBJIWDPuoi72o8iTIDg==" url="https://files.vmpal.com/macos/0.36/VMPal.dmg"></enclosure><description>&#xA;        &lt;h2&gt;Build 36 - Virtual Machines for Apple Silicon&lt;/h2&gt;&#xA;        &lt;h4&gt;Release date: 6 October 2026&lt;/h4&gt;&#xA;        &lt;ol&gt;&#xA;          &lt;li&gt;Bug fixes and improvements.&lt;/li&gt;&#xA;        &lt;/ol&gt;&#xA;      </description><title>Build 36 - Virtual Machines for Apple Silicon</title><pubDate>Tue, 06 Oct 2026 03:52:59 +0000</pubDate><minimumSystemVersion>26.0</minimumSystemVersion></item><title>VMPal</title></channel></rss>
"""#

/// Field values match the real bundle mounted from
/// `https://files.vmpal.com/macos/0.36/VMPal.dmg` on 2026-10-06:
/// `CFBundleIdentifier` = `com.tableplus.VMPal`, short "0.36", build "36", no
/// `SUFeedURL`, `SUPublicEDKey` as below.
///
/// The path is made up on purpose and asserted absent: nothing here may depend
/// on what this host has installed.
private func vmPalApp(shortVersion: String, buildVersion: String) -> InstalledApp {
    let path = "/Applications/ZZFixture-VMPal.app"
    #expect(!FileManager.default.fileExists(atPath: path),
            "fixture path \(path) exists on this host")
    return InstalledApp(
        name: "VMPal", bundleID: "com.tableplus.VMPal",
        shortVersion: shortVersion, buildVersion: buildVersion,
        path: URL(fileURLWithPath: path),
        isMASApp: false,
        sparkleFeedURL: SparkleFeedCatalog.feed(forBundleID: "com.tableplus.VMPal"),
        sparkleEdPublicKey: "YgOe15pkgXV0xxPbMgyl8C//gU3vl48M7xDYTW0w2BM=")
}

@Suite struct VMPalCoverageTests {
    private var items: [SparkleAppcastItem] {
        SparkleAppcastParser.parse(
            Data(vmPalFeedFixture.utf8), relativeTo: URL(string: "https://vmpal.com/apps/version.xml"))
    }

    /// The bundle id is mixed-case; the catalog key is lowercase and the lookup
    /// lowercases, so the real spelling has to resolve.
    @Test func catalogSuppliesTheFeedTheBundleDoesNotDeclare() {
        #expect(SparkleFeedCatalog.feed(forBundleID: "com.tableplus.VMPal")?.absoluteString
            == "https://vmpal.com/apps/version.xml")
    }

    /// The Sparkle attributes on `<enclosure>` resolve through the namespace the
    /// element declares on itself, so version, signature and download all read.
    @Test func olderInstallIsOfferedTheSignedDmg() {
        let app = vmPalApp(shortVersion: "0.35", buildVersion: "35")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.0")
        #expect(best?.shortVersionString == "0.36")
        #expect(best?.version == "36")
        #expect(best?.enclosureURL?.absoluteString == "https://files.vmpal.com/macos/0.36/VMPal.dmg")
        #expect(best?.edSignature?.isEmpty == false)
    }

    @Test func upToDateInstallMatchesTheTopOfFeedExactly() {
        let app = vmPalApp(shortVersion: "0.36", buildVersion: "36")
        let best = SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "26.0")
        let installed = VersionSide(marketing: app.shortVersion, build: app.buildVersion)
        let remote = VersionSide(marketing: best?.shortVersionString, build: best?.version)
        #expect(VersionComparator.isSame(installed, as: remote))
        #expect(VersionComparator.isNewer(remote, than: installed) == false)
    }

    /// Why no `ChannelBinding`: nothing in the feed tags a channel.
    @Test func realFeedCarriesNoChannelTags() {
        #expect(items.allSatisfy { $0.channel == nil })
    }

    /// Pins the claim in the catalog comment: the unprefixed
    /// `<minimumSystemVersion>` is not read as Sparkle's floor. If the parser
    /// ever starts reading it, this goes red and the comment must change too.
    @Test func unprefixedMinimumSystemVersionIsNotRead() {
        #expect(items.count == 1)
        #expect(items.first?.minimumSystemVersion == nil)
    }
}
