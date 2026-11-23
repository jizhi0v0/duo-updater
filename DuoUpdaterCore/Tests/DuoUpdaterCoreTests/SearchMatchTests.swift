import Testing
import Foundation
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

    /// Turkish pairs I with ı and İ with i, so a fold under tr_TR alone loses
    /// plain ASCII matches, and a fold with no locale loses the dotless ı.
    @Test(arguments: [
        ("GITHUB", "GitHub"),
        ("izinler", "İzinler"),
        ("IZINLER", "İzinler"),
        ("ı", "Install"),
        ("icloud", "iCloud"),
    ])
    func turkishLocaleKeepsBothFolds(query: String, text: String) {
        #expect(SearchMatch.matches(query, in: text, locale: Locale(identifier: "tr_TR")))
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

    @Test func appNamePrefixesLeadSubstringsAndExcludeBundleIDNoise() {
        let apps: [(name: String, bundleID: String?)] = [
            ("AdGuard", "com.adguard.mac"),
            ("Amp", "dev.amp"),
            ("Microsoft Word", "com.microsoft.Word"),
            ("Mac Mouse Fix", nil),
            ("Gemini", nil),
        ]
        let matches = SearchMatch.rankedApps(" ｍ ", in: apps, name: \.name, bundleID: \.bundleID)
        #expect(matches.apps.map(\.name) == ["Microsoft Word", "Mac Mouse Fix", "Amp", "Gemini"])
        #expect(matches.bundleIDOnly.isEmpty)
        let unfiltered = SearchMatch.rankedApps("  ", in: apps, name: \.name, bundleID: \.bundleID)
        #expect(unfiltered.apps.map(\.name) == apps.map(\.name))
        #expect(unfiltered.bundleIDOnly.isEmpty)
    }

    @Test func dottedQueriesKeepBundleIDsAfterNameMatches() {
        let apps: [(name: String, bundleID: String?)] = [
            ("Google Chrome", "com.google.Chrome"),
            ("My com.google Inspector", nil),
            ("com.google Tool", "com.google.Chrome"),
        ]
        let matches = SearchMatch.rankedApps("ＣＯＭ．ＧＯＯＧＬＥ", in: apps, name: \.name, bundleID: \.bundleID)
        #expect(matches.apps.map(\.name) == ["com.google Tool", "My com.google Inspector", "Google Chrome"])
        #expect(matches.bundleIDOnly.map(\.name) == ["Google Chrome"])
    }
}
