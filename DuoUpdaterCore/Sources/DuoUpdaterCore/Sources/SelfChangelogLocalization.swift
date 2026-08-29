import Foundation

/// Which file Duo Updater's own release notes should be read from for the
/// language the app is running in, and how a translation that covers only part of
/// the history is folded onto the English original.
///
/// The English `CHANGELOG.md` stays authoritative. It is the file
/// `publish-release.sh` lifts each release's section out of, it is the only one
/// guaranteed to carry every version, and it alone fixes the order the window
/// shows. A translation is a *substitution over that spine*: where
/// `changelog/<lang>.md` has a section for a version, its prose replaces the
/// English prose for that version; where it doesn't, the English stands. So
/// history is never truncated by a translation being behind, and coverage can be
/// extended one release at a time without a migration.
///
/// Deliberately in Core rather than next to the view: this is the part with rules
/// in it, `App/Sources` has no test target, and the same substitution has to hold
/// for a language file that is empty, stale, ahead of English, or absent.
public enum SelfChangelogLocalization {

    /// The base name of the translated notes file for the app's effective
    /// language, or nil when there is nothing to fetch.
    ///
    /// Takes `Bundle.main.preferredLocalizations` — already resolved by macOS
    /// against the localizations the app actually ships, so its first element is
    /// one of our own `.lproj` names ("de", "zh-Hans", …) and needs no mapping of
    /// its own. That resolution is the point: the notes then come back in the same
    /// language as the window around them, rather than in whatever the user's
    /// region happens to imply.
    ///
    /// nil for English (that file *is* the English notes — fetching it twice would
    /// buy nothing) and nil for an empty list. **No allowlist of supported
    /// languages**: a hand-kept list is one more thing to forget when a language is
    /// added, and the server already answers the question — a file that isn't there
    /// 404s and the caller keeps English, which is the same outcome the list would
    /// have produced.
    public static func translatedNotesBasename(preferredLocalizations: [String]) -> String? {
        guard let first = preferredLocalizations.first, !first.isEmpty else { return nil }
        guard first != "en", !first.hasPrefix("en-"), !first.hasPrefix("en_") else { return nil }
        // Path component, and it is about to be interpolated into a URL. Anything
        // that isn't a plain language tag is not a language we ship.
        guard first.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return first
    }

    /// Translated prose substituted onto the English spine, version by version.
    ///
    /// The English changelog decides which versions exist, what order they appear
    /// in, and each entry's `version` and `date` — a translation carries prose, not
    /// facts about the release. A version the translation doesn't cover keeps its
    /// English text, and a version the translation has but English doesn't is
    /// dropped rather than appended: that combination means the translation is
    /// ahead of, or has drifted from, the file it is a translation of, and showing
    /// notes for a release the authoritative file has never heard of is worse than
    /// showing nothing.
    ///
    /// `itemSyntax` comes from English too. Both files are our own Markdown with a
    /// bold lead sentence per paragraph; a translation cannot change what the
    /// renderer should do with it.
    public static func merge(english: Changelog, translated: Changelog?) -> Changelog {
        guard let translated, !translated.entries.isEmpty else { return english }

        // First writer wins, matching the parser's own reading of a duplicated
        // heading: the section nearer the top of the file is the newer one.
        var byVersion: [String: Changelog.Entry] = [:]
        for entry in translated.entries where byVersion[entry.version] == nil {
            byVersion[entry.version] = entry
        }

        let entries = english.entries.map { entry -> Changelog.Entry in
            guard let localized = byVersion[entry.version], !localized.items.isEmpty
            else { return entry }
            return Changelog.Entry(
                title: localized.title ?? entry.title,
                version: entry.version,
                date: entry.date,
                items: localized.items,
                content: entry.content)
        }
        return Changelog(entries: entries, itemSyntax: english.itemSyntax)
    }
}
