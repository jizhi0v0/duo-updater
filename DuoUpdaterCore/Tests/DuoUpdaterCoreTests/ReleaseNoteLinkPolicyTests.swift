import Testing
import Foundation
@testable import DuoUpdaterCore

/// Which links inside rendered release notes the app will open on a click.
///
/// Notes are vendor-controlled text. SwiftUI's default `openURL` hands whatever
/// the link says to `NSWorkspace`, so `[x](smb://host/share)`, `ssh:`,
/// `shortcuts:` or any other registered scheme would launch its handler.
@Suite struct ReleaseNoteLinkPolicyTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func httpsAndMailtoAreOpened() {
        for s in [
            "https://example.com/changelog",
            "HTTPS://Example.com/Notes",
            "https://github.com/o/r/releases/tag/v1.0",
            "mailto:support@example.com",
            "MAILTO:support@example.com?subject=hi",
        ] {
            #expect(ReleaseNoteLinkPolicy.allows(url(s)), "\(s) should open")
        }
    }

    @Test func everyOtherSchemeIsDiscarded() {
        for s in [
            "http://example.com/notes",
            "smb://host/share",
            "ssh://user@host",
            "afp://host/vol",
            "vnc://host",
            "shortcuts://run-shortcut?name=x",
            "x-apple.systempreferences:com.apple.preference.security",
            "file:///Applications/Calculator.app",
            "ftp://example.com/file",
            "tel:+15555550100",
            "javascript:alert(1)",
            "data:text/html,hi",
            "duoupdater:5",
        ] {
            #expect(!ReleaseNoteLinkPolicy.allows(url(s)), "\(s) should be discarded")
        }
    }

    /// A relative reference has no scheme to vouch for it.
    @Test func aSchemelessLinkIsDiscarded() {
        #expect(!ReleaseNoteLinkPolicy.allows(url("/relative/path")))
        #expect(!ReleaseNoteLinkPolicy.allows(url("example.com/notes")))
    }

    /// The links a Markdown note really carries, parsed the way the changelog
    /// views parse them (`.inlineOnlyPreservingWhitespace`), so the policy is
    /// exercised on `AttributedString` link runs and not only on hand-built URLs.
    @Test func linkRunsOfAParsedNoteAreFilteredByScheme() throws {
        let note = "See [docs](https://example.com/d), [share](smb://evil/share) "
            + "and [mail](mailto:a@b.example)."
        let parsed = try AttributedString(
            markdown: note, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let links = parsed.runs.compactMap(\.link)
        #expect(links.count == 3)
        #expect(links.filter(ReleaseNoteLinkPolicy.allows).map(\.scheme) == ["https", "mailto"])
    }
}
