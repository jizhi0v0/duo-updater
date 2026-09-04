import Testing
import Foundation
@testable import DuoUpdaterCore

/// What the request log looks like once it *leaves* the machine — the NDJSON a
/// dump prints or saves, and the URL the window puts on the pasteboard.
///
/// Both are here because both had the same failure mode: a rule that was applied
/// at one call site and forgotten at another, with nothing executing either.
/// `duo events` abbreviated the home directory, `duo requests --json` and the
/// window's Export did not — the same rows out of the same store, answering
/// differently depending on which one you asked.
struct RequestLogExportTests {

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private static func row(payload: String) -> EventRow {
        EventRow(
            id: UUID(), date: Date(), client: .app, kind: "request", payloadJSON: payload)
    }

    private static func event(path: String, scheme: String = "https", port: Int? = nil)
        -> RequestEvent
    {
        RequestEvent(
            purpose: .install, method: "GET", scheme: scheme, host: "dl.example.com",
            port: port, path: path, taskID: UUID(), hopIndex: 0, redirectCount: 0,
            status: 200, fetchType: .networkLoad,
            requestHeaderBytes: 0, requestBodyBytes: 0,
            responseHeaderBytes: 0, responseBodyBytes: 0)
    }

    // MARK: - The dump

    /// Mutation: `exportJSON` returning `json`.
    @Test("A bundle under the home directory is abbreviated on the way out")
    func exportAbbreviatesTheHomeDirectory() {
        let row = Self.row(payload: #"{"appID":"\#(Self.home)/Applications/Espanso.app"}"#)
        #expect(row.exportJSON.contains("~/Applications/Espanso.app"))
        #expect(!row.exportJSON.contains(Self.home))
        // The raw form is deliberately still raw: this asserts the two differ, so
        // a "simplification" that collapses them fails here rather than in a dump
        // nobody reads until it is already pasted somewhere.
        #expect(row.json.contains(Self.home))
    }

    /// Mutation: abbreviating anything else — replacing `/Applications` or the
    /// leading `/Users` wholesale rather than this account's own home.
    @Test("A bundle outside the home directory is emitted untouched")
    func exportLeavesSystemPathsAlone() {
        let row = Self.row(payload: #"{"appID":"/Applications/WorkBuddy AI.app"}"#)
        #expect(row.exportJSON.contains("/Applications/WorkBuddy AI.app"))
        #expect(!row.exportJSON.contains("~"))
    }

    // MARK: - The pasteboard

    /// Mutation: `path` concatenated raw, as it was.
    ///
    /// A literal space is not exotic here — it is what Mozilla, Bartender and
    /// Termius download paths decode to, 18 of 590 distinct paths on one real
    /// machine.
    ///
    /// Who actually breaks on the unescaped form was measured rather than
    /// assumed, because the answer is narrower than it looks: Swift's own
    /// `URL(string:)` repairs the space to `%20` on the way in, and so do
    /// browsers — so `#require` below would pass either way, and it is not what
    /// this case is testing. `curl` is the one that does not forgive it: given
    /// the raw string it exits 3 and sends nothing at all, so the copied URL
    /// fetches nothing in the one place you would paste it to fetch something.
    @Test("A path with a space is escaped, and the result parses back to that path")
    func copiedURLEscapesSpacesAndRoundTrips() throws {
        let stored = "/pub/firefox/releases/155.0/mac/en-US/Firefox 155.0.dmg"
        let copied = Self.event(path: stored).url

        // The escaping itself is the assertion; the round-trip below only checks
        // that escaping did not change which request the URL names.
        #expect(copied.contains("Firefox%20155.0.dmg"))
        let parsed = try #require(URL(string: copied))
        // Round-trip rather than string equality: this is the property Copy URL
        // actually owes — paste it back and you get the request that was made.
        #expect(parsed.path == stored)
        #expect(parsed.host == "dl.example.com")
    }

    /// Mutation: escaping with `.urlHostAllowed`, or hand-rolling a space-only
    /// replacement.
    ///
    /// `?` and `#` are the ones no parser rescues, and the only ones where the
    /// old behaviour was silently *wrong* rather than merely unfetchable: given
    /// `/d/a?b#c/file.zip` raw, `URL(string:)` reads path `/d/a`, query `b` and
    /// fragment `c/file.zip` — measured. So the copy named a different request
    /// than the one that was made, and invented a query string for a row whose
    /// query was deliberately never recorded.
    ///
    /// No path on the machine measured above contains either character. This is
    /// the class of hole that has no instances until it has one.
    @Test("A path containing ? or # cannot turn into a query or a fragment")
    func copiedURLEscapesQueryAndFragmentSeparators() throws {
        let stored = "/d/a?b#c/file.zip"
        let parsed = try #require(URL(string: Self.event(path: stored).url))

        #expect(parsed.path == stored)
        #expect(parsed.query == nil)
        #expect(parsed.fragment == nil)
    }

    /// Mutation: dropping the port clause, or escaping the whole assembled string
    /// (which would eat the `://` and the port colon).
    @Test("Escaping the path leaves the scheme, host and non-default port intact")
    func copiedURLKeepsTheAuthority() {
        #expect(Self.event(path: "/a b", scheme: "http", port: 8080).url
            == "http://dl.example.com:8080/a%20b")
        #expect(Self.event(path: "/a b", scheme: "http", port: 80).url
            == "http://dl.example.com/a%20b")
    }
}
