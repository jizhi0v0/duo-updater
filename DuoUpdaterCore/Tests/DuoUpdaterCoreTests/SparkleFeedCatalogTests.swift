import Testing
import Foundation
@testable import DuoUpdaterCore

/// `SparkleFeedCatalog` — the address for an app that ships Sparkle but whose
/// `Info.plist` does not give us a usable one: the app keeps it in code
/// (`feeds`), or it names a feed the vendor has abandoned (`supersededFeeds`).
/// Its whole reason for existing is that it must NOT behave like
/// `ChannelBinding.feedOverride`, so most of what is worth asserting here is
/// about the boundary between the two.
struct SparkleFeedCatalogTests {

    /// Every bundle id the catalog answers for, whichever table it sits in. The
    /// derived tests below iterate this rather than `feeds`: a superseding entry
    /// hands `AppScanner` an address exactly the way a fill-in does, so every
    /// invariant about an address the catalog supplies has to cover both, and a
    /// test that quietly means "the fill-in table" leaves the other one uncovered
    /// the day it gains its first entry — which it just did.
    private static var allKeys: [String] {
        Array(SparkleFeedCatalog.feeds.keys) + Array(SparkleFeedCatalog.supersededFeeds.keys)
    }

    /// Every URL the catalog hands to the fetcher, with the key it came from.
    /// A superseded entry's `declared` half is deliberately NOT here: it is a
    /// match key, never fetched and never a base for resolving an enclosure, so
    /// the https requirement below would be asserting a reason that does not
    /// apply to it — and abandoned appcasts from the 2010s are routinely plain
    /// `http`, which is a shape this table must be able to record.
    private static var allFeeds: [(key: String, url: URL)] {
        SparkleFeedCatalog.feeds.map { ($0.key, $0.value) }
            + SparkleFeedCatalog.supersededFeeds.map { ($0.key, $0.value.live) }
    }

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
        for key in Self.allKeys {
            #expect(key == key.lowercased(), "catalog key is not lowercase: \(key)")
        }
        for key in SparkleFeedCatalog.feeds.keys {
            #expect(SparkleFeedCatalog.feed(forBundleID: key) != nil,
                    "catalog key is unreachable through feed(forBundleID:): \(key)")
        }
        for (key, entry) in SparkleFeedCatalog.supersededFeeds {
            #expect(SparkleFeedCatalog.replacement(
                forBundleID: key, declaredFeed: entry.declared) == entry.live,
                    "superseded key is unreachable through replacement(forBundleID:declaredFeed:): \(key)")
        }
    }

    /// Every feed here has to be absolute and http(s): it is handed straight to
    /// `URLSession`, and — since the parser now resolves an appcast's contents
    /// against the feed URL — it is also the base every enclosure inside is
    /// resolved against. A relative or schemeless entry would poison both.
    @Test func everyFeedIsAnAbsoluteHTTPURL() {
        for (key, url) in Self.allFeeds {
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
        for key in Self.allKeys {
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
        for key in Self.allKeys {
            #expect(ChangelogCatalog.url(forBundleID: key) != nil
                    || ChangelogRecipeRegistry.recipe(forBundleID: key) != nil,
                    "\(key) is fed by SparkleFeedCatalog but has no changelog source")
        }
    }

    // MARK: - Superseded feeds

    /// PDF Expert's `SUFeedURL` names `/release/appcast.xml`, frozen since July
    /// 2022 at build 764 (2.5.22). Three of its four items cap out below macOS 11,
    /// but the fourth does not, so a current Mac resolves that feed, reads 2.5.22
    /// as the newest release, finds it older than the installed 3.13.2 and calls
    /// the app up to date — permanently, and without an error anywhere. The live
    /// feed is the `pem3` one, which the app reaches in code.
    @Test func pdfExpertIsMovedOffTheFeedItsBundleStillNames() {
        #expect(SparkleFeedCatalog.replacement(
            forBundleID: "com.readdle.PDFExpert-Mac",
            declaredFeed: URL(string: "https://downloads.pdfexpert.com/release/appcast.xml"))?
            .absoluteString == "https://downloads.pdfexpert.com/pem3/release/appcast.xml")
    }

    /// The property that keeps a superseding entry from being a permanent pin.
    /// The match is on the DEAD ADDRESS, not on the bundle id: the day Readdle
    /// edits `SUFeedURL` — to the pem3 feed, or to a fourth address we have never
    /// seen — the entry stops applying and the bundle's own word wins again. A
    /// bundle-id lookup would instead keep asserting our 2026 reading of their
    /// infrastructure over theirs, forever, and look identical while doing it.
    @Test func aSupersedingEntryOnlyFiresOnTheExactDeadAddress() {
        for (key, entry) in SparkleFeedCatalog.supersededFeeds {
            #expect(SparkleFeedCatalog.replacement(forBundleID: key, declaredFeed: entry.live) == nil,
                    "\(key): the live feed must not be superseded by itself")
            #expect(SparkleFeedCatalog.replacement(
                forBundleID: key,
                declaredFeed: URL(string: "https://example.invalid/appcast.xml")) == nil,
                    "\(key): an unrecognized address must be honoured, not replaced")
            // An app that names nothing is a `feeds` question, never this one.
            #expect(SparkleFeedCatalog.replacement(forBundleID: key, declaredFeed: nil) == nil)
            #expect(SparkleFeedCatalog.replacement(
                forBundleID: "com.example.nope", declaredFeed: entry.declared) == nil)
            // Same case-insensitivity as every other lookup here — bundle ids are
            // conventionally lowercase but nothing guarantees it.
            #expect(SparkleFeedCatalog.replacement(
                forBundleID: key.uppercased(), declaredFeed: entry.declared) == entry.live)
        }
    }

    /// What a `declared` address does have to be: something a bundle could
    /// actually state, and something the comparison can match. Scheme-relative or
    /// path-only entries would never equal a `SUFeedURL` `AppScanner` parsed, so
    /// the entry would be dead on arrival and look fine.
    @Test func everyDeclaredAddressIsAbsoluteAndSchemed() {
        for (key, entry) in SparkleFeedCatalog.supersededFeeds {
            #expect(entry.declared.host != nil, "\(key): declared feed has no host")
            #expect(entry.declared.scheme?.hasPrefix("http") == true,
                    "\(key): declared feed is not http(s) — \(entry.declared)")
        }
    }

    /// Replacing a feed with itself would be a no-op entry that reads like a
    /// working one — the shape a stale entry takes after a vendor fixes their
    /// plist and someone edits only half of this table.
    @Test func noSupersedingEntryPointsAtItself() {
        for (key, entry) in SparkleFeedCatalog.supersededFeeds {
            #expect(entry.declared != entry.live, "\(key): declared and live feed are the same URL")
        }
    }

    /// An app cannot be in both tables: `feeds` answers when the bundle named no
    /// feed and `supersededFeeds` when it named a dead one, so an entry in both
    /// means one of them is describing a state the other has already claimed.
    @Test func noAppIsInBothTables() {
        let both = Set(SparkleFeedCatalog.feeds.keys)
            .intersection(SparkleFeedCatalog.supersededFeeds.keys)
        #expect(both.isEmpty, "in both catalog tables: \(both.sorted())")
    }

    /// The wiring, end to end through `AppScanner.readApp(at:)` — the table being
    /// right buys nothing if the scan never consults it. Three synthetic bundles,
    /// because the three answers have to be distinguishable from one another:
    /// the dead address is replaced, a different address is left exactly as
    /// stated, and an app not in the table keeps its own feed.
    @Test func theScanSwapsTheDeadAddressAndLeavesEveryOtherOneAlone() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("duo-superseded-feed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        func bundle(_ name: String, id: String, feed: String) throws -> URL {
            let app = root.appendingPathComponent("\(name).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(
                at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": id,
                "CFBundleName": name,
                "CFBundleShortVersionString": "3.13.2",
                "CFBundleVersion": "1172",
                "SUFeedURL": feed,
            ]
            try PropertyListSerialization
                .data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }

        let scanner = AppScanner()
        let dead = "https://downloads.pdfexpert.com/release/appcast.xml"
        let live = "https://downloads.pdfexpert.com/pem3/release/appcast.xml"

        let onDead = try #require(scanner.readApp(at: try bundle(
            "PDF Expert", id: "com.readdle.PDFExpert-Mac", feed: dead)))
        #expect(onDead.sparkleFeedURL?.absoluteString == live)

        // The vendor moving their plist to a fourth address (or fixing it) is not
        // a case this table gets to answer.
        let moved = try #require(scanner.readApp(at: try bundle(
            "PDF Expert Moved", id: "com.readdle.PDFExpert-Mac",
            feed: "https://downloads.pdfexpert.com/pem4/release/appcast.xml")))
        #expect(moved.sparkleFeedURL?.absoluteString
            == "https://downloads.pdfexpert.com/pem4/release/appcast.xml")

        // And the address itself is not a redirect for everyone who names it.
        let other = try #require(scanner.readApp(at: try bundle(
            "Not PDF Expert", id: "com.example.other", feed: dead)))
        #expect(other.sparkleFeedURL?.absoluteString == dead)
    }

    // MARK: - What `duo verify` sweeps

    /// `verificationCases` is what the nightly sweep iterates (#324). It is
    /// derived from the two tables rather than written out beside them, and
    /// this pins the derivation: an entry with no case is an address nothing
    /// fetches, which is the exact state that issue was filed about.
    @Test func everyCatalogEntryIsSwept() {
        let cases = SparkleFeedCatalog.verificationCases
        #expect(cases.count == SparkleFeedCatalog.feeds.count
                + SparkleFeedCatalog.supersededFeeds.count)
        #expect(Set(cases.map(\.recipeID)).count == cases.count,
                "two entries share a sweep key, so one of them would overwrite the other's baseline row")
        // Sorted, because the sweep prints in this order and the baseline is
        // written in it — deriving from a dictionary without sorting would
        // reshuffle both from run to run.
        #expect(cases.map(\.recipeID) == cases.map(\.recipeID).sorted())

        for (key, url) in SparkleFeedCatalog.feeds {
            let entry = cases.first { $0.bundleID == key }
            #expect(entry?.kind == .fillIn)
            #expect(entry?.feed == url)
            // A fill-in overrides nothing, so there is no second address to
            // read — and the sweep's expiry check keys on this being nil.
            #expect(entry?.declared == nil)
        }
        for (key, superseded) in SparkleFeedCatalog.supersededFeeds {
            let entry = cases.first { $0.bundleID == key }
            #expect(entry?.kind == .superseded)
            // The LIVE address is the one an app is actually pointed at, so it
            // is the one worth sweeping; `declared` rides along because the
            // entry is only justified while that address stays behind.
            #expect(entry?.feed == superseded.live)
            #expect(entry?.declared == superseded.declared)
        }
    }
}
