import Testing
import Foundation
@testable import DuoUpdaterCore

/// A copy installed from the Mac App Store must not be handed a feed address
/// that came from `SparkleFeedCatalog` (#368).
///
/// Both of that table's halves supply an address the BUNDLE never stated — the
/// fill-in invents one outright, the superseded entry redirects one we decided
/// was dead. Inventing an address for a copy the store owns is not the scanner's
/// business whatever happens downstream.
///
/// ⚠️ Downstream has since changed, and this file's original framing was wrong
/// twice over. It said `MacAppStoreSource` "returns nil rather than throwing" —
/// it does both, and the throw is the case that mattered, because
/// `UpdateChecker` falls through on a thrown error too. And it said a store copy
/// reaching `SparkleAppcastSource` was the harm to prevent; that source now
/// declines store copies along with every other non-store source, via
/// `UpdateChecker`'s gate (see `SourceStorePolicyTests`). So these two lines are
/// belt and braces now: what they still decide is what the scanner is entitled
/// to WRITE DOWN, which is a different question from who may answer.
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
            // The store copy keeps the dead address it declared. That used to
            // matter — it meant a frozen 2022 feed could answer and report "up to
            // date" — and it was filed as #385 for that reason. The store gate
            // closed it: no store copy reaches `SparkleAppcastSource` at all, so
            // the recorded address has no consumer. Kept as an assertion because
            // it still pins WHICH address the scanner writes down, and a redirect
            // appearing here would be the scanner making a choice it should not.
            #expect(store.sparkleFeedURL == entry.declared,
                    "\(bundleID): a store copy was redirected to a feed we chose for it")
        }
    }

    /// The other side of the same decision: the `SUFeedURL` read records what the
    /// bundle SAYS, which is a fact, not a decision, and the scanner does not
    /// edit it by install kind.
    ///
    /// ⚠️ Do not read this as "a store copy's own feed is honoured" — it is not,
    /// not any more. `UpdateChecker`'s gate declines every non-store source for a
    /// store row, so the address recorded here has no consumer. The earlier
    /// version of this comment justified the split with "Keka is a real store
    /// copy carrying `SUFeedURL`", which was never true: Developer ID-signed, no
    /// `_MASReceipt`.
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
