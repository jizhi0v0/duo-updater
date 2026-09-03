import Testing
import Foundation
@testable import DuoUpdaterCore

/// `SparkleFeedCatalog` — the address for an app that ships Sparkle but keeps its
/// feed URL in code. Its whole reason for existing is that it must NOT behave
/// like `ChannelBinding.feedOverride`, so most of what is worth asserting here is
/// about the boundary between the two.
struct SparkleFeedCatalogTests {

    @Test func heliumResolvesToItsArm64Appcast() {
        #expect(SparkleFeedCatalog.feed(forBundleID: "net.imput.helium")?.absoluteString
            == "https://updates.helium.computer/mac/appcast-arm64.xml")
    }

    @Test func lookupIsCaseInsensitiveAndMissesCleanly() {
        #expect(SparkleFeedCatalog.feed(forBundleID: "NET.IMPUT.Helium") != nil)
        #expect(SparkleFeedCatalog.feed(forBundleID: "com.example.nope") == nil)
        #expect(SparkleFeedCatalog.feed(forBundleID: nil) == nil)
    }

    /// Derived from the table, so a new entry is covered the day it lands.
    /// `feed(forBundleID:)` lowercases its argument, so a key carrying a capital
    /// is unreachable — `ChangelogCatalog` shipped exactly that bug once
    /// (`net.whatsapp.WhatsApp`) and its fallback never resolved.
    @Test func keysAreLowercasedSoEveryEntryIsReachable() {
        for key in SparkleFeedCatalog.feeds.keys {
            #expect(key == key.lowercased(), "catalog key is not lowercase: \(key)")
            #expect(SparkleFeedCatalog.feed(forBundleID: key) != nil,
                    "catalog key is unreachable through feed(forBundleID:): \(key)")
        }
    }

    /// Every feed here has to be absolute and http(s): it is handed straight to
    /// `URLSession`, and — since the parser now resolves an appcast's contents
    /// against the feed URL — it is also the base every enclosure inside is
    /// resolved against. A relative or schemeless entry would poison both.
    @Test func everyFeedIsAnAbsoluteHTTPURL() {
        for (key, url) in SparkleFeedCatalog.feeds {
            #expect(url.scheme == "https", "\(key): feed is not https — \(url)")
            #expect(url.host != nil, "\(key): feed has no host — \(url)")
        }
    }

    /// The boundary that makes this type worth having. A bundle in BOTH tables
    /// would get its address from `ChannelBinding`, which also declares the
    /// channel authoritative — switching off the feed-based channel inference
    /// this catalog exists to preserve. Whichever one you meant, having both is
    /// not it.
    @Test func noEntryIsAlsoManagedByAChannelBinding() {
        for key in SparkleFeedCatalog.feeds.keys {
            #expect(ChannelBinding.resolve(bundleID: key) == nil,
                    Comment(rawValue: "\(key) is in SparkleFeedCatalog AND has a "
                        + "ChannelBinding — the binding wins and makes the channel "
                        + "authoritative, which is what this catalog exists to avoid"))
        }
    }

    /// The catalog supplies an address; it must not also claim to know the track.
    /// With no `ChannelBinding`, an app carrying a catalog feed reaches
    /// `allowedChannels` as non-authoritative, so the channel is read off the
    /// feed's own items — a default build sees only untagged entries, a
    /// beta-tagged build unlocks its own train. This is Helium's real feed shape.
    @Test func aCatalogFedAppStillInfersItsChannelFromTheFeed() {
        let items = SparkleAppcastParser.parse(Data("""
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
        <channel>
          <item>
            <title>0.16.2.1</title>
            <sparkle:version>0.16.2.1</sparkle:version>
            <sparkle:shortVersionString>0.16.2.1</sparkle:shortVersionString>
            <enclosure url="assets/helium_0.16.2.1_arm64-macos.dmg" length="1"
                       sparkle:edSignature="sig" type="application/octet-stream"/>
          </item>
          <item>
            <title>0.16.1.1</title>
            <sparkle:version>0.16.1.1</sparkle:version>
            <sparkle:shortVersionString>0.16.1.1</sparkle:shortVersionString>
            <sparkle:channel>beta</sparkle:channel>
            <enclosure url="assets/helium_0.16.1.1_arm64-macos.dmg" length="1"
                       sparkle:edSignature="sig" type="application/octet-stream"/>
          </item>
        </channel>
        </rss>
        """.utf8), relativeTo: SparkleFeedCatalog.feed(forBundleID: "net.imput.helium"))

        func helium(_ version: String) -> InstalledApp {
            InstalledApp(
                name: "Helium", bundleID: "net.imput.helium",
                shortVersion: version, buildVersion: version,
                path: URL(fileURLWithPath: "/Applications/Helium.app"),
                isMASApp: false,
                sparkleFeedURL: SparkleFeedCatalog.feed(forBundleID: "net.imput.helium"),
                releaseChannel: .stable,
                // What `AppScanner` produces for a catalog feed: an address, and
                // no claim about the track.
                channelIsAuthoritative: false)
        }

        // The default build never sees the beta item.
        let onDefault = SparkleAppcastSource.usableItems(
            for: helium("0.16.2.1"), from: items, osVersion: "26.0.0")
        #expect(onDefault.map(\.version) == ["0.16.2.1"])

        // The beta build unlocks its own train — by BEING that build, with no
        // vendor preference read anywhere.
        let onBeta = SparkleAppcastSource.usableItems(
            for: helium("0.16.1.1"), from: items, osVersion: "26.0.0")
        #expect(Set(onBeta.map(\.version)) == ["0.16.2.1", "0.16.1.1"])

        // And the relative enclosure resolved against the catalog's own URL.
        #expect(onDefault.first?.enclosureURL?.absoluteString
            == "https://updates.helium.computer/mac/assets/helium_0.16.2.1_arm64-macos.dmg")
    }

    /// Moving Helium onto its own feed costs the GitHub release body it used to
    /// render as notes — that appcast carries no `<description>` and no
    /// `sparkle:releaseNotesLink`. The changelog fallback has to cover it, or the
    /// notes pane goes quietly empty.
    @Test func everyCatalogFeedAppHasAChangelogFallback() {
        for key in SparkleFeedCatalog.feeds.keys {
            #expect(ChangelogCatalog.url(forBundleID: key) != nil
                    || ChangelogRecipeRegistry.recipe(forBundleID: key) != nil,
                    "\(key) is fed by SparkleFeedCatalog but has no changelog source")
        }
    }
}
