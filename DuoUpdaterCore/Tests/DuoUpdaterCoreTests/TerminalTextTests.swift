import Testing
import Foundation
@testable import DuoUpdaterCore

/// What a vendor controls and `duo verify` prints (`TerminalText`).
@Suite struct TerminalTextTests {

    /// An OSC 52 clipboard write, a window retitle, a CSI cursor move and colour,
    /// an OSC 8 hyperlink: the visible text stays, every escape goes.
    ///
    /// Mutation: have `printable` return its input.
    @Test func escapeSequencesAreRemoved() {
        let esc = "\u{1B}"
        #expect(TerminalText.printable("1.2.3\(esc)]52;c;ZXZpbA==\u{07}") == "1.2.3")
        #expect(TerminalText.printable("a\(esc)]0;title\(esc)\\b") == "ab")
        #expect(TerminalText.printable("\(esc)[2J\(esc)[1;1Hdone\(esc)[0m") == "done")
        #expect(TerminalText.printable("\(esc)]8;;https://evil.example\u{07}link\(esc)]8;;\u{07}") == "link")
    }

    /// An unterminated OSC loses its introducer, so what follows is text.
    @Test func anUnterminatedOSCIsNotLeftActive() {
        let cleaned = TerminalText.printable("v\u{1B}]52;c;ZXZpbA==")
        #expect(!cleaned.unicodeScalars.contains("\u{1B}"))
    }

    /// What `stripEscapes` leaves: bare C0, DEL, and C1 — `U+009B` is CSI and
    /// `U+009D` is OSC on a terminal that reads 8-bit controls. Newlines go too,
    /// so a value cannot forge a line of report output.
    ///
    /// Mutation: drop the control-character filter.
    @Test func controlCharactersAreRemovedExceptTab() {
        #expect(TerminalText.printable("a\u{07}b\u{08}c\u{7F}d\u{9B}31me\u{9D}0;t\u{9C}f") == "abcd31me0;tf")
        #expect(TerminalText.printable("one\ntwo\r\n  resolved  9.9") == "onetwo  resolved  9.9")
        #expect(TerminalText.printable("a\tb") == "a\tb")
    }

    @Test func ordinaryTextIsUntouched() {
        for text in ["1.2.3-beta.4+build5", "版本 2.0 — ✓ ok", "naïve résumé", ""] {
            #expect(TerminalText.printable(text) == text)
        }
    }
}
