import Testing
@testable import DuoUpdaterCore

/// The rule every search field shares — popover, workbench and Settings sidebar.
@Suite struct SearchMatchTests {
    @Test(arguments: [
        ("Café", "cafe"),
        ("Zürich", "ZURICH"),
        ("Notificações", "notificacoes"),
        ("Größe", "große"),
        ("Ελλάδα", "ελλαδα"),
        ("通知", "通知"),
    ])
    func foldsCaseAndDiacritics(text: String, query: String) {
        #expect(SearchMatch.matches(query, in: text))
    }

    /// A CJK input method left in full-width mode types these. Width is the fold
    /// `localizedStandardContains`, the popover's old predicate, did not make.
    @Test func foldsFullWidthLatin() {
        #expect(SearchMatch.matches("ｘｃｏｄ", in: "Xcode"))
        #expect(SearchMatch.matches("xcod", in: "Ｘｃｏｄｅ"))
        #expect(!"Xcode".localizedStandardContains("ｘｃｏｄ"))
    }

    @Test func blankQueryMatchesEverything() {
        #expect(SearchMatch.matches("  ", in: "Xcode"))
        #expect(SearchMatch.matches("", in: [String?]()))
    }

    @Test func trimsTheQuery() {
        #expect(SearchMatch.matches(" xcode \n", in: "Xcode"))
        #expect(SearchMatch.trimmed(" a b ") == "a b")
    }

    @Test func anyFieldMatchesAndNilsAreSkipped() {
        #expect(SearchMatch.matches("com.google", in: ["Google Chrome", "com.google.Chrome"]))
        #expect(SearchMatch.matches("chrome", in: [nil, "Google Chrome"]))
        #expect(!SearchMatch.matches("safari", in: ["Google Chrome", nil]))
    }

    @Test func doesNotMatchUnrelatedText() {
        #expect(!SearchMatch.matches("xcodes", in: "Xcode"))
    }
}
