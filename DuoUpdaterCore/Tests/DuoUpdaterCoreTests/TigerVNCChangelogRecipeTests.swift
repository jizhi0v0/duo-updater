import Foundation
import Testing

@testable import DuoUpdaterCore

/// Four releases from `api.github.com/repos/TigerVNC/tigervnc/releases`
/// (fetched 2026-10-10), each picked for a decision the recipe makes. Bodies are
/// verbatim except v1.15.90, trimmed by whole lines to its first two items.
///
/// - v1.16.2: prose only, then the SourceForge/Regards footer.
/// - v1.16.0: an intro sentence, an indented `  - ` list, a footnote, the footer.
/// - v1.15.90: a beta, `prerelease: true`.
/// - v1.3.0: `\n` line endings and the older "You can download binary builds"
///   footer.
private let tigerVNCReleasesFixture = #"""
[
 {
  "tag_name": "v1.16.2",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-03-26T20:49:14Z",
  "body": "This is a second attempt at a bug fix release for the security issue in x0vncserver. The TigerVNC 1.16.1 release unfortunately had all fixes except the security fix.\r\n\r\nApologies for the extra noise and confusion.\r\n\r\nBinaries are available from SourceForge:\r\n\r\nhttps://sourceforge.net/projects/tigervnc/files/stable/1.16.2\r\n\r\nRegards\r\nThe TigerVNC Developers"
 },
 {
  "tag_name": "v1.16.0",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-01-27T14:57:18Z",
  "body": "TigerVNC 1.16.0 is now available. Lots of changes have been made since the last release, but the highlights are:\r\n\r\n  - The native viewer has a new keyboard shortcut system to control the viewer, replacing the F8 shortcut and allowing easier access to toggle full-screen mode and redirecting system keys\r\n  - The native viewer now supports sending system keys even in windowed mode\r\n  - Added a new server called w0vncserver for sharing Wayland desktops\r\n  - The Java viewer has more fine-grained control of scaling the session\r\n  - The native viewer uses a different method to intercept system keys on macOS, which will require explicit user approval\r\n  - The native viewer has an improved server field, with searchable history\r\n  - The native viewer now intercepts and forwards all¹ system keys on Windows\r\n  - The native viewer is now more responsive when resizing the remote session\r\n  - Red Hat Enterprise Linux 10 packages have been added, although without libvnc.so\r\n  - Ubuntu 20.04 and Red Hat Enterprise Linux 7 packages have been removed\r\n\r\n¹ except for Ctrl+Alt+Delete, which can never be intercepted\r\n\r\nBinaries are available from SourceForge:\r\n\r\nhttps://sourceforge.net/projects/tigervnc/files/stable/1.16.0\r\n\r\nRegards\r\nThe TigerVNC Developers"
 },
 {
  "tag_name": "v1.15.90",
  "prerelease": true,
  "draft": false,
  "published_at": "2025-11-25T06:56:37Z",
  "body": "A beta of TigerVNC 1.16.0 is now available. Lots of changes have been made since\r\nthe last release, but the highlights are:\r\n\r\n  - The native viewer has a new keyboard shortcut system to control the viewer, replacing the F8 shortcut and allowing easier access to toggle full-screen mode and redirecting system keys\r\n  - The native viewer now supports sending system keys even in windowed mode"
 },
 {
  "tag_name": "v1.3.0",
  "prerelease": false,
  "draft": false,
  "published_at": "2014-06-30T11:41:21Z",
  "body": "After over a year, we've finally finished a new version of TigerVNC. A lot of fixes and new features have gone into this new release. The big higlights are:\n- Full multi-head support.\n- Improved keyboard support in Xvnc.\n- Listen mode is back in both viewers.\n- SSH tunneling is back on Unix and in the Java viewer.\n- Edge/bump scrolling in full screen mode.\n- The viewers can now store and load settings.\n- Better full screen support in the Java viewer.\n- Dynamic resize of sessions as you resize the viewer.\n- Several performance improvements in the Java viewer.\n\nYou can download binary builds from our old Sourceforge page:\n\nhttps://sourceforge.net/projects/tigervnc/files/tigervnc/1.3.0/\n\nRegards\nThe TigerVNC Developers\n"
 }
]
"""#

@Suite struct TigerVNCChangelogRecipeTests {

    private func parsed() throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.tigervnc.tigervnc"))
        return try #require(ChangelogService.parse(recipe, body: tigerVNCReleasesFixture))
    }

    @Test func readsTheStableReleases() throws {
        let entries = try parsed().entries
        #expect(entries.map(\.version) == ["1.16.2", "1.16.0", "1.3.0"])
        #expect(entries.first?.date == "2026-03-26")
    }

    /// The footer is not a change: on a list-less body the decoder's prose pass
    /// read it as three of five items.
    @Test func aProseReleaseKeepsItsParagraphsAndDropsTheFooter() throws {
        let newest = try #require(try parsed().entries.first)
        #expect(newest.items == [
            "This is a second attempt at a bug fix release for the security issue in x0vncserver. The TigerVNC 1.16.1 release unfortunately had all fixes except the security fix.",
            "Apologies for the extra noise and confusion.",
        ])
    }

    @Test func aListReleaseKeepsTheListOnly() throws {
        let entries = try parsed().entries
        let list = try #require(entries.first { $0.version == "1.16.0" })
        #expect(list.items.count == 10)
        #expect(list.items.first == "The native viewer has a new keyboard shortcut system to control the viewer, replacing the F8 shortcut and allowing easier access to toggle full-screen mode and redirecting system keys")
        #expect(list.items.contains("The native viewer now intercepts and forwards all¹ system keys on Windows"))
        let old = try #require(entries.first { $0.version == "1.3.0" })
        #expect(old.items.count == 9)
        #expect(old.items.first == "Full multi-head support.")
    }

    @Test func noEntryCarriesTheFooter() throws {
        let items = try parsed().entries.flatMap(\.items)
        #expect(!items.contains { $0.contains("SourceForge") || $0.contains("Sourceforge") })
        #expect(!items.contains { $0 == "Regards" || $0.contains("TigerVNC Developers") })
    }
}
