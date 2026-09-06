import Testing
import Foundation
@testable import DuoUpdaterCore

/// A copy installed from the Mac App Store must not be handed a feed address
/// that came from `SparkleFeedCatalog` (#368).
///
/// Both of that table's halves supply an address the BUNDLE never stated — the
/// fill-in invents one outright, the superseded entry redirects one we decided
/// was dead. For a store copy that turns a store lookup which merely missed
/// (`MacAppStoreSource` returns nil rather than throwing, and `SourceStack` runs
/// `SparkleAppcastSource` third) into a one-click direct-install download beside
/// an app the store owns. `HomebrewCaskSource`, `GitHubReleasesSource` and
/// `VendorProbeSource` all carry the same `guard !app.isMASApp`.
///
/// Driven off the registry, not off a written-down list of bundle ids: a new
/// catalog entry is covered the day it lands. Every case names the mutation it
/// catches.
struct AppScannerStoreCopyTests {

    /// Plants a bundle and returns the row `AppScanner` reads out of it.
    ///
    /// `_MASReceipt/receipt` is the store marker the scanner actually looks for.
    /// Each case asserts `isMASApp` on the result rather than assuming the
    /// fixture earned it — a fixture that quietly stopped reading as a store copy
    /// would make every store half of this file vacuously green.
    private static func scan(
        bundleID: String, declaringFeed feed: String?, storeReceipt: Bool
    ) throws -> InstalledApp {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("scanner-store-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("Fixture.app")
        var plist: [String: Any] = [
            "CFBundleDisplayName": "Fixture",
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "100",
        ]
        if let feed { plist["SUFeedURL"] = feed }
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: info.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0).write(to: info)
        if storeReceipt {
            let receipt = bundle.appendingPathComponent("Contents/_MASReceipt/receipt")
            try fm.createDirectory(at: receipt.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try Data("not a real receipt".utf8).write(to: receipt)
        }
        defer { try? fm.removeItem(at: root) }
        return try #require(AppScanner().scan(bundlesAt: [bundle]).first)
    }

    /// Mutation: `if feedURL == nil, !isMAS` → `if feedURL == nil`. The store half
    /// then gets the curated address and the row is offered a direct download.
    @Test func aFilledInFeedGoesToDirectCopiesAndNotToStoreCopies() throws {
        try #require(!SparkleFeedCatalog.feeds.isEmpty)
        for (bundleID, feed) in SparkleFeedCatalog.feeds {
            let direct = try Self.scan(
                bundleID: bundleID, declaringFeed: nil, storeReceipt: false)
            #expect(!direct.isMASApp)
            #expect(direct.sparkleFeedURL == feed,
                    "\(bundleID): a direct copy stating no feed should get the curated one")

            let store = try Self.scan(
                bundleID: bundleID, declaringFeed: nil, storeReceipt: true)
            #expect(store.isMASApp, "\(bundleID): fixture stopped reading as a store copy")
            #expect(store.sparkleFeedURL == nil,
                    "\(bundleID): a store copy was handed a feed address it never stated")
        }
    }

    /// Mutation: drop `!isMAS,` from the `SparkleFeedCatalog.replacement` guard.
    /// The store half is then redirected off the frozen feed — which reads
    /// harmlessly as up-to-date — and onto a live one that offers a .zip.
    @Test func aSupersededFeedIsRedirectedForDirectCopiesOnly() throws {
        try #require(!SparkleFeedCatalog.supersededFeeds.isEmpty)
        for (bundleID, entry) in SparkleFeedCatalog.supersededFeeds {
            let declared = entry.declared.absoluteString
            let direct = try Self.scan(
                bundleID: bundleID, declaringFeed: declared, storeReceipt: false)
            #expect(!direct.isMASApp)
            #expect(direct.sparkleFeedURL == entry.live,
                    "\(bundleID): a direct copy on the dead address should move to the live one")

            let store = try Self.scan(
                bundleID: bundleID, declaringFeed: declared, storeReceipt: true)
            #expect(store.isMASApp, "\(bundleID): fixture stopped reading as a store copy")
            // ⚠️ This pins today's answer, not a settled one. What the store copy
            // is left with is an address we have OURSELVES recorded as dead, so a
            // run where the store lookup misses reads a frozen feed and reports
            // "up to date" rather than "Managed by the App Store". Honouring a
            // declared feed is the Keka rule; honouring one we know is worthless
            // is not obviously the same thing. Filed as #385 — if that is settled
            // the other way, this expectation is the thing to change.
            #expect(store.sparkleFeedURL == entry.declared,
                    "\(bundleID): a store copy was redirected to a feed we chose for it")
        }
    }

    /// The other side of the same decision, and the one that keeps this from
    /// being "store copies never get a Sparkle feed": an address the BUNDLE
    /// states is the app speaking for itself and is honoured whoever installed
    /// it. Keka is a real store copy carrying `SUFeedURL`; `UpdateChecker`'s
    /// "all sources exhausted" comment names it for the same reason.
    ///
    /// Mutation: extend the guard to the `SUFeedURL` read and this goes nil.
    @Test func aStoreCopyKeepsTheFeedItsOwnBundleStates() throws {
        let stated = "https://example.com/keka-shaped-appcast.xml"
        let app = try Self.scan(
            bundleID: "com.example.storecopy", declaringFeed: stated, storeReceipt: true)
        #expect(app.isMASApp)
        #expect(app.sparkleFeedURL?.absoluteString == stated)
    }
}
