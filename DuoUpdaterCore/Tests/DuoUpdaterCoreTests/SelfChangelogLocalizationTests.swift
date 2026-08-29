import Foundation
import Testing
@testable import DuoUpdaterCore

// MARK: - Which file to fetch

@Test func englishAsksForNoTranslation() {
    #expect(SelfChangelogLocalization.translatedNotesBasename(preferredLocalizations: ["en"]) == nil)
    #expect(SelfChangelogLocalization.translatedNotesBasename(preferredLocalizations: ["en-US"]) == nil)
    #expect(SelfChangelogLocalization.translatedNotesBasename(preferredLocalizations: []) == nil)
    #expect(SelfChangelogLocalization.translatedNotesBasename(preferredLocalizations: [""]) == nil)
}

@Test func theFirstResolvedLocalizationNamesTheFile() {
    // `preferredLocalizations` is already resolved against what the app ships, so
    // the head of the list is an .lproj name and is used verbatim.
    #expect(SelfChangelogLocalization.translatedNotesBasename(
        preferredLocalizations: ["zh-Hans", "en"]) == "zh-Hans")
    #expect(SelfChangelogLocalization.translatedNotesBasename(
        preferredLocalizations: ["de"]) == "de")
}

/// The basename goes straight into a URL path. A tag that isn't a plain language
/// tag is not a language we ship, and must not be able to steer the request.
@Test func aNonLanguageTagIsRefusedRatherThanInterpolated() {
    for junk in ["../../etc/passwd", "de/../../x", "zh Hans", "de?x=1", "de#f", "de%2e"] {
        #expect(SelfChangelogLocalization.translatedNotesBasename(preferredLocalizations: [junk]) == nil,
                "\(junk) should not reach a URL")
    }
}

// MARK: - Merging

private func entry(_ version: String, _ items: [String], date: String? = nil) -> Changelog.Entry {
    Changelog.Entry(version: version, date: date, items: items)
}

@Test func aVersionTheTranslationCoversIsSubstituted() {
    let english = Changelog(entries: [entry("2.0", ["new two"]), entry("1.0", ["new one"])],
                            itemSyntax: .markdown)
    let translated = Changelog(entries: [entry("2.0", ["neu zwei"])], itemSyntax: .markdown)
    let merged = SelfChangelogLocalization.merge(english: english, translated: translated)

    #expect(merged.entries.map(\.version) == ["2.0", "1.0"])
    #expect(merged.entries[0].items == ["neu zwei"])
    // Not covered — English stands rather than the row going missing.
    #expect(merged.entries[1].items == ["new one"])
    #expect(merged.itemSyntax == .markdown)
}

@Test func versionAndDateAlwaysComeFromEnglish() {
    let english = Changelog(entries: [entry("2.0", ["new two"], date: "2026-08-29")])
    let translated = Changelog(entries: [entry("2.0", ["neu zwei"], date: "irgendwann")])
    let merged = SelfChangelogLocalization.merge(english: english, translated: translated)

    #expect(merged.entries[0].version == "2.0")
    #expect(merged.entries[0].date == "2026-08-29")
}

@Test func aTranslationAheadOfEnglishIsDroppedNotAppended() {
    let english = Changelog(entries: [entry("1.0", ["new one"])])
    let translated = Changelog(entries: [entry("9.9", ["from the future"]), entry("1.0", ["eins"])])
    let merged = SelfChangelogLocalization.merge(english: english, translated: translated)

    #expect(merged.entries.map(\.version) == ["1.0"])
    #expect(merged.entries[0].items == ["eins"])
}

@Test func anAbsentOrEmptyTranslationLeavesEnglishUntouched() {
    let english = Changelog(entries: [entry("1.0", ["new one"])], itemSyntax: .markdown)
    #expect(SelfChangelogLocalization.merge(english: english, translated: nil) == english)
    #expect(SelfChangelogLocalization.merge(english: english, translated: Changelog(entries: [])) == english)
    // A section that parsed to no prose is not a translation of anything.
    let empty = Changelog(entries: [entry("1.0", [])])
    #expect(SelfChangelogLocalization.merge(english: english, translated: empty) == english)
}

// MARK: - The live files
//
// Derived from the app's own localization table and from CHANGELOG.md, never from
// a list written here: a hand-kept list is exactly what stops being true the day a
// language is added.

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // DuoUpdaterCoreTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // DuoUpdaterCore
    .deletingLastPathComponent()   // repo root

/// Every language the app ships, other than English, taken from the string table.
private func shippedTranslations() throws -> [String] {
    let url = repoRoot.appendingPathComponent("App/Resources/Localizable.xcstrings")
    let data = try Data(contentsOf: url)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    var langs = Set<String>()
    for value in strings.values {
        guard let entry = value as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any] else { continue }
        langs.formUnion(localizations.keys)
    }
    langs.remove("en")
    #expect(!langs.isEmpty, "the string table named no languages — the shape drifted")
    return langs.sorted()
}

private func englishChangelog() throws -> Changelog {
    let url = repoRoot.appendingPathComponent("CHANGELOG.md")
    let text = try #require(try? String(contentsOf: url, encoding: .utf8))
    return try #require(SelfChangelogParser.parse(text))
}

private func englishVersions() throws -> [String] {
    try englishChangelog().entries.map(\.version)
}

/// A translation is one paragraph per English paragraph, because one paragraph is
/// one row in the window. Merging two of them, or dropping the one that was only a
/// sentence long, doesn't fail anything downstream — it just quietly shows a
/// reader in that language fewer changes than actually shipped, and nothing else
/// in the pipeline would ever say so.
@Test func everyShippedLanguageHasANotesFileMatchingEnglishParagraphForParagraph() throws {
    let english = try englishChangelog()
    let englishItemCounts = Dictionary(
        english.entries.map { ($0.version, $0.items.count) }, uniquingKeysWith: { first, _ in first })

    for lang in try shippedTranslations() {
        let url = repoRoot.appendingPathComponent("changelog/\(lang).md")
        let text = try #require(try? String(contentsOf: url, encoding: .utf8),
                                "changelog/\(lang).md is missing — the app ships \(lang) and would silently show English notes in it")
        let log = try #require(SelfChangelogParser.parse(text),
                               "changelog/\(lang).md carried no release sections")
        #expect(log.entries.allSatisfy { !$0.items.isEmpty && !$0.version.isEmpty })

        for entry in log.entries {
            guard let expected = englishItemCounts[entry.version] else { continue }
            #expect(entry.items.count == expected,
                    "\(lang) \(entry.version): \(entry.items.count) paragraphs against English's \(expected) — the window would show a different number of changes")
        }
        // The bold lead sentence is the whole readability of these notes, and the
        // renderer is told to treat them as Markdown. A paragraph that lost its
        // `**` renders as an undifferentiated wall next to ones that kept it.
        for entry in log.entries {
            #expect(entry.items.allSatisfy { $0.hasPrefix("**") },
                    "\(lang) \(entry.version): a paragraph does not open with a bold lead sentence")
        }
    }
}

/// The translations move together, and they cover a hole-free run of the newest
/// releases. Neither is cosmetic: a language quietly left behind reads to its
/// speakers as "Duo Updater stopped writing release notes", and a hole in the
/// middle of the run is a window that changes language halfway down.
///
/// Deliberately NOT "covers the newest English version": that would fail the
/// moment a release is published and before its translations are written, turning
/// this guard into something to be disabled on release day.
@Test func translationsCoverTheSameHoleFreeRunOfRecentVersions() throws {
    let english = try englishVersions()
    let rank = Dictionary(uniqueKeysWithValues: english.enumerated().map { ($0.element, $0.offset) })

    let languages = try shippedTranslations()
    var covered: [String: [String]] = [:]
    for lang in languages {
        let url = repoRoot.appendingPathComponent("changelog/\(lang).md")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let log = SelfChangelogParser.parse(text) else { continue }
        covered[lang] = log.entries.map(\.version)
    }
    // Without this the test passes by having nothing to check: a language whose
    // file went missing or stopped parsing would drop out of the loop above and
    // take its own coverage requirement with it.
    #expect(covered.count == languages.count,
            "no readable notes file for \(languages.filter { covered[$0] == nil })")
    let reference = try #require(covered.values.first)

    for (lang, versions) in covered.sorted(by: { $0.key < $1.key }) {
        #expect(Set(versions) == Set(reference),
                "\(lang) covers a different set of versions than the other translations")

        let ranks = versions.map { rank[$0] }
        #expect(ranks.allSatisfy { $0 != nil },
                "\(lang) has a section for a version CHANGELOG.md doesn't list: \(versions.filter { rank[$0] == nil })")
        let ordered = ranks.compactMap { $0 }
        #expect(ordered == ordered.sorted(),
                "\(lang) lists versions in a different order than CHANGELOG.md")
        if let first = ordered.first, let last = ordered.last {
            #expect(last - first + 1 == ordered.count,
                    "\(lang) skips versions inside the run it covers")
        }
    }
}
