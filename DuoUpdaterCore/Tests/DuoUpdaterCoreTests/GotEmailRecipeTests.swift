import Testing
import Foundation
@testable import DuoUpdaterCore

/// GotEmail's What's New: `releases.json` read by `.gotEmailReleases`. The recipe
/// comes from the registry, not restated.
struct GotEmailRecipeTests {

    /// `https://gotemail.shipcat.app/releases.json`, 2026-10-09, verbatim except
    /// that 0.1.1 and 0.1.0 are cut.
    private static let body = #"""
        {
          "releases": [
            {
              "version": "0.1.3",
              "date": "2026-10-09",
              "items": [
                {
                  "tag": "changed",
                  "text": "When a provider refuses the password, the account form now says what to do in plain words (Gmail, iCloud, Yahoo, AOL, Fastmail and Zoho all need an app password, not the account password) and opens the page where you make one."
                },
                {
                  "tag": "new",
                  "text": "AOL is a preset: pick it and the servers are filled in."
                },
                {
                  "tag": "changed",
                  "text": "Outlook.com, Hotmail, Live and Microsoft 365 addresses get a note before Connect: Microsoft only allows its own sign-in, which is coming in a later update."
                }
              ]
            },
            {
              "version": "0.1.2",
              "date": "2026-10-09",
              "items": [
                {
                  "tag": "new",
                  "text": "Send from any of your account's addresses. Add them under \"Also send as\" in Edit Account (a custom domain on iCloud+, a Gmail \"send mail as\" address): they appear in the From menu, and a reply to mail sent to one of them goes out from it."
                }
              ]
            }
          ]
        }
        """#

    private static func decode(_ body: String, maxEntries: Int? = 20) -> Changelog? {
        StructuredChangelogDecoder.decode(body, format: .gotEmailReleases, channel: nil, maxEntries: maxEntries)
    }

    @Test func theRecipeReadsReleasesJSON() throws {
        let matches = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == "com.voprex.gotemail" }
        try #require(matches.count == 1)
        #expect(matches[0].source.absoluteString == "https://gotemail.shipcat.app/releases.json")
        #expect(matches[0].structuredFormat == .gotEmailReleases)
    }

    /// Document order, each line led by its tag, as the vendor's page shows it.
    @Test func linesKeepTheirTagAndOrder() throws {
        let changelog = try #require(Self.decode(Self.body))
        #expect(changelog.entries.map(\.version) == ["0.1.3", "0.1.2"])
        let newest = changelog.entries[0]
        #expect(newest.date == "2026-10-09")
        #expect(newest.items.count == 3)
        #expect(newest.items[0].hasPrefix("Changed: When a provider refuses the password"))
        #expect(newest.items[1] == "New: AOL is a preset: pick it and the servers are filled in.")
        #expect(newest.items[2].hasPrefix("Changed: Outlook.com"))
        #expect(changelog.entries[1].items[0].contains(#""Also send as""#))
        #expect(try #require(Self.decode(Self.body, maxEntries: 1)).entries.count == 1)
    }

    /// The file is edited by hand. Like the page: a non-object is skipped, an
    /// unknown or missing tag reads as Changed, a release with no lines is left out.
    @Test func handEditsReadLikeThePage() throws {
        let body = #"""
            {"releases": [
              "stray",
              {"version": "0.2.0", "date": "2026-11-01", "items": [
                null,
                {"tag": "FIXED", "text": "Upper-case tag."},
                {"tag": "improved", "text": "Unknown tag."},
                {"text": "No tag."},
                {"tag": "new", "text": "  "}
              ]},
              {"version": "0.1.9", "items": []},
              {"items": [{"tag": "new", "text": "No version."}]}
            ]}
            """#
        let changelog = try #require(Self.decode(body))
        #expect(changelog.entries.map(\.version) == ["0.2.0"])
        #expect(changelog.entries[0].items == ["Fixed: Upper-case tag.", "Changed: Unknown tag.", "Changed: No tag."])
        #expect(Self.decode(#"{"releases": []}"#) == nil)
        #expect(Self.decode("<html></html>") == nil)
    }
}
