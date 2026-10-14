import Foundation

/// The one "does this text contain what was typed" rule behind every search field:
/// the menu-bar popover, the workbench, and the Settings sidebar. One rule so the
/// same query never finds an app in one window and misses it in the next.
///
/// Folds case, diacritics and character width:
///
/// - **Diacritics** — "cafe" finds "Café", "zurich" finds "Zürich",
///   "notificacoes" finds "Notificações".
/// - **Width** — "ｘｃｏｄ" finds "Xcode". A Chinese or Japanese input method
///   left in full-width mode types Latin letters as their full-width forms, and
///   without this a search that looks right on screen finds nothing.
///   `localizedStandardContains`, which the popover and workbench used before,
///   does not fold width.
/// - **Case, twice** — once with no locale and once under the reader's, and
///   either is a match. Neither alone is enough, measured 2026-10-14 under
///   tr_TR: the locale-aware fold (what `localizedStandardContains` did) misses
///   "GITHUB" → "GitHub" and "izinler" → "İzinler", because Turkish pairs I with
///   ı and İ with i; the locale-free fold (what Settings did) misses "ı" →
///   "Install". Taking both means nothing either old predicate found is lost.
///
/// Also measured 2026-10-14, en_US: accents, ß and Greek tonos fold in both.
/// Neither folds half-width katakana into full-width (ﾊﾞｯｸｱｯﾌﾟ vs バックアップ),
/// nor reads a hyphen as a space, nor German "ue" as "ü".
public enum SearchMatch {
    /// The query as the fields read it: surrounding whitespace dropped.
    public static func trimmed(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` contains `query`. A blank query matches everything.
    public static func matches(_ query: String, in text: String) -> Bool {
        matches(query, in: text, locale: .current)
    }

    /// `matches(_:in:)` under a given reader's locale, so tests can pin one.
    static func matches(_ query: String, in text: String, locale: Locale) -> Bool {
        let needle = trimmed(query)
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return text.range(of: needle, options: options) != nil
            || text.range(of: needle, options: options, locale: locale) != nil
    }

    /// Whether any of `texts` contains `query`; nils are skipped. A blank query
    /// matches everything, even an empty list.
    public static func matches(_ query: String, in texts: [String?]) -> Bool {
        guard !trimmed(query).isEmpty else { return true }
        return texts.contains { $0.map { matches(query, in: $0) } ?? false }
    }
}
