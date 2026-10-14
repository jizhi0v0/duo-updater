import Foundation

/// The one "does this text contain what was typed" rule behind every search field:
/// the menu-bar popover, the workbench, and the Settings sidebar. One rule so the
/// same query never finds an app in one window and misses it in the next.
///
/// Folds case, diacritics and character width, under the reader's locale:
///
/// - **Diacritics** — "cafe" finds "Café", "zurich" finds "Zürich",
///   "notificacoes" finds "Notificações".
/// - **Width** — "ｘｃｏｄ" finds "Xcode". A Chinese or Japanese input method
///   left in full-width mode types Latin letters as their full-width forms, and
///   without this a search that looks right on screen finds nothing.
///   `localizedStandardContains`, which the popover and workbench used before,
///   does not fold width.
/// - **Locale** — case folding follows the reader's language rules.
///
/// Measured 2026-10-14, en_US, against the two predicates this replaces
/// (`localizedStandardContains` in the popover and workbench, and
/// `range(of:options: [.caseInsensitive, .diacriticInsensitive])` in Settings):
/// all three agreed on accents, ß, Turkish İ and Greek tonos; only this one
/// matched full-width Latin. None folds half-width katakana into full-width
/// (ﾊﾞｯｸｱｯﾌﾟ vs バックアップ), and none reads a hyphen as a space.
public enum SearchMatch {
    /// The query as the fields read it: surrounding whitespace dropped.
    public static func trimmed(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` contains `query`. A blank query matches everything.
    public static func matches(_ query: String, in text: String) -> Bool {
        let needle = trimmed(query)
        guard !needle.isEmpty else { return true }
        return text.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current) != nil
    }

    /// Whether any of `texts` contains `query`; nils are skipped. A blank query
    /// matches everything, even an empty list.
    public static func matches(_ query: String, in texts: [String?]) -> Bool {
        guard !trimmed(query).isEmpty else { return true }
        return texts.contains { $0.map { matches(query, in: $0) } ?? false }
    }
}
