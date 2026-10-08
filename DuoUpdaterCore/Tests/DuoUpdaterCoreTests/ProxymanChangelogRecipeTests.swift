import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases from `api.github.com/repos/ProxymanApp/Proxyman/releases`
/// (fetched 2026-10-08), with only the fields the decoder reads. 26.0.1's body is
/// whole. 26.0.0's is trimmed to two Features bullets, one Improvement and two
/// Bug Fixes, with its `## Screenshots` section kept whole: captions, an `<img>`
/// and a bare video link. `1.0` is the repo's one GitHub prerelease (2018), whole,
/// from `/releases/tags/1.0`; it is a bulleted body that would parse, so it is the
/// real case for the stable filter. Everything kept is verbatim.
private let proxymanReleasesFixture = #"""
[
 {
  "tag_name": "26.0.1",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-09-27T14:45:28Z",
  "body": "## Improvements\n- Large JSON bodies no longer freeze the app when opening the Tree View.\n- Connection logs now show more details about why HTTP/2 streams close.\n\n## Bug Fixes\n- HOTFIX: Crashed when using HTTP/2 for some users\n- Fixed a crash when undoing URL edits after switching requests.\n- Fixed sidebar selections being lost when clearing a session.\n- Fixed incorrect error messages for DNS and HTTP/2 failures.\n- Fixed JSON formatting for bodies with extra padding at the end.\n\n"
 },
 {
  "tag_name": "26.0.0",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-09-21T08:41:53Z",
  "body": "## Features\r\n- Support macOS 27 Golden Gate\r\n- Proxyman can capture HTTP/2 traffic, work with all debugging tools, back-compatible with Map Local, Breakpoint, Scripting and Compose Tool\r\n\r\n## Improvements\r\n- Revamp the Tab View of Proxyman, make it lightweight and more responsive.\r\n\r\n## Bug Fixes\r\n- Fixed: Upload and download speeds shows wrong values.\r\n- Fixed Scripting changing decimal number formats in JSON bodies.\r\n\r\n## Screenshots\r\n- HTTP/2 and Connection Log\r\n<img width=\"1440\" height=\"1310\" alt=\"Screenshot 2026-09-18 at 11 00 20\" src=\"https://github.com/user-attachments/assets/4d5a4b98-9380-446a-9938-a2ecc4500615\" />\r\n\r\n- Split View\r\n\r\nhttps://github.com/user-attachments/assets/7fd0b5aa-f805-4ec1-bf43-86962f2d85e8\r\n\r\n"
 },
 {
  "tag_name": "1.0",
  "prerelease": true,
  "draft": false,
  "published_at": "2018-10-25T08:02:20Z",
  "body": "## Changelogs 😍\r\n+ 100x faster by native ProxymanCore\r\n+ 38x faster to identify which App (pid) the request comes from\r\n+ HTTP/HTTPS Proxying.\r\n+ Remove all 3rd libraries\r\n+ Reduce size from 28Mb -> 12Mb"
 }
]
"""#

@Suite struct ProxymanChangelogRecipeTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.proxyman.NSProxy", channel: .stable, version: "26.0.1"))
    }

    /// Parsed the way the app parses it: `ChangelogService.parse` with the
    /// registered recipe, so `skipSections` and `channel` are the shipped ones.
    private func parsed() throws -> Changelog {
        try #require(ChangelogService.parse(try recipe(), body: proxymanReleasesFixture))
    }

    @Test func readsTheReleasesAPIOnTheStableTrack() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.mode == .json)
        #expect(r.channel == .stable)
        #expect(r.tagPattern == nil)
        #expect(r.source.host == "api.github.com")
        #expect(r.source.path == "/repos/ProxymanApp/Proxyman/releases")
        #expect(r.source.query == "per_page=20")
        #expect(r.maxEntries == 15)
        #expect(r.skipSections == ["Screenshots"])
    }

    /// The tag is the bundle's short version as-is, and the 2018 prerelease is
    /// not on the stable rail.
    @Test func versionsAreTheTagsAndThePrereleaseIsDropped() throws {
        let log = try parsed()
        #expect(log.entries.map(\.version) == ["26.0.1", "26.0.0"])
        #expect(log.entries.map(\.date) == ["2026-09-27", "2026-09-21"])
        #expect(log.itemSyntax == .markdown)
    }

    @Test func theNewestEntryKeepsItsCategoryHeadings() throws {
        let entry = try #require(try parsed().entries.first)
        #expect(entry.items.count == 7)
        #expect(entry.items.first == "Large JSON bodies no longer freeze the app when opening the Tree View.")
        #expect(entry.items.last == "Fixed JSON formatting for bodies with extra padding at the end.")
        #expect(headings(entry) == ["Improvements", "Bug Fixes"])
    }

    /// `## Screenshots` holds image captions, not changes: without the skip,
    /// "Split View" would sit in the rail as a change of its own.
    @Test func theScreenshotsSectionIsDropped() throws {
        let entry = try #require(try parsed().entries.dropFirst().first)
        #expect(entry.version == "26.0.0")
        #expect(entry.items.count == 5)
        #expect(headings(entry) == ["Features", "Improvements", "Bug Fixes"])
        #expect(!entry.items.contains("Split View"))
        #expect(!entry.items.contains("HTTP/2 and Connection Log"))
        #expect(!entry.items.contains { $0.contains("<img") || $0.contains("user-attachments") })
    }

    /// The skip is what removes those captions; the same body parsed with no
    /// `skipSections` still carries them. Keeps the test above from passing
    /// for some other reason.
    @Test func withoutTheSkipTheCaptionsWouldBeItems() throws {
        let bare = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            proxymanReleasesFixture, channel: .stable, maxEntries: 15))
        let entry = try #require(bare.entries.dropFirst().first)
        #expect(entry.items.count == 7)
        #expect(entry.items.suffix(2) == ["HTTP/2 and Connection Log", "Split View"])
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { block in
            if case .heading(let h) = block { return h }
            return nil
        }
    }
}
