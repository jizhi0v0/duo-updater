import Foundation

/// Whether a Requests-pane date range is honoured by what the event store
/// actually retains, and what to say when it is not (#460).
///
/// The range menu offers "Last 7 days" whether or not the store has kept
/// anything close to seven days of events, and until now nothing on screen
/// said so — the caption hid the only clue (the retention floor) the moment a
/// range was picked, and the status bar never carried it at all. Fixing that
/// is a rule ("given the floor and a range, is it honoured, and what do we
/// say"), and rules belong here rather than in `RequestLogPane`: that file
/// imports SwiftUI, and `App/project.yml`'s comment on `DuoUpdaterAppTests`
/// explains why nothing in that target may. This file has no SwiftUI import
/// and no `AppListModel` dependency so the test target can compile it.
///
/// `RequestLogPane` calls ``annotation(since:floor:now:)`` once per
/// `Range` case for the picker's menu labels, and ``relativeDescription(of:relativeTo:locale:)``
/// for the caption and the status bar — the same "how far back, in words"
/// question asked in a neutral voice instead of a warning.
enum RequestCoverageHonesty {
    /// What a range's menu row should say about the gap between what it
    /// promises and what the store can actually back it with, or `nil` when
    /// the promise is honoured.
    ///
    /// - Parameters:
    ///   - since: the range's cutoff (`RequestLogPane.Range.since`). `nil`
    ///     means "All time", which promises nothing to fall short of, so this
    ///     always returns `nil` for it — the range enum is not referenced
    ///     directly here (see the file comment on why), but every case maps to
    ///     exactly this `since` value.
    ///   - floor: the store's retention floor —
    ///     `EventStore.coverage(kind: "request").oldest`, unfiltered by
    ///     whatever the user has typed or selected. Using the filtered
    ///     `RequestLogSummary.oldest` here instead would make the annotation
    ///     describe the current query rather than the store, and it would
    ///     disappear the moment a range was picked — which is the bug this
    ///     type exists to fix.
    ///   - now: injected rather than read from the clock, so the answer does
    ///     not depend on when or where the test runs.
    ///   - locale: forwarded to ``relativeDescription(of:relativeTo:locale:)``.
    ///     Defaulted to `.current` for real callers (the point of a relative
    ///     phrase is to match the device's own locale), but a test that does
    ///     not pin this explicitly is a test that asks the host what locale it
    ///     is in — CLAUDE.md's 2026-09-09 rule. Before this parameter existed,
    ///     `annotation` had no way to avoid that: it always fell through to
    ///     `.current` with no seam for a test to inject anything else, so
    ///     `note?.contains("19")` only passed on a host whose locale renders
    ///     Western digits.
    ///
    /// `floor == nil` (the store holds no request events at all) is treated as
    /// *not* honouring any range that has a cutoff — fail closed, matching
    /// this repo's other "can't tell → don't claim it" rules — rather than as
    /// vacuously honouring every range. An empty store has kept nothing, so
    /// nothing it promises is backed by data.
    static func annotation(
        since: Date?, floor: Date?, now: Date = Date(), locale: Locale = .current
    ) -> String? {
        guard let since else { return nil }
        guard let floor else {
            return String(localized: "no requests recorded yet")
        }
        guard floor > since else { return nil }
        let span = relativeDescription(of: floor, relativeTo: now, locale: locale)
        return String(localized: "records only go back to \(span)")
    }

    /// The retention floor in words — "19 hours ago", "3 days ago" — rather
    /// than a calendar month. A 19-hour window rendered as "since September
    /// 2026" is not a lie, but the month-granularity template it replaced
    /// (`RequestLogPane.monthYear`, `MMMyyyy`) erased the magnitude: it read
    /// as "recording since the start of the month" when the store in fact
    /// goes back to 1:47 that same morning.
    ///
    /// The unit words ("hours", "days") come from `RelativeDateTimeFormatter`,
    /// i.e. from Foundation's own localization rather than from
    /// `Localizable.xcstrings` — which is what keeps the catalog entries this
    /// change adds down to whole phrases with one placeholder each, instead of
    /// a set of plural rules per supported unit per language.
    static func relativeDescription(
        of date: Date, relativeTo now: Date = Date(), locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The caption and status-bar phrasing — a neutral statement of fact, not
    /// a warning about an unmet promise (that is ``annotation(since:floor:now:)``).
    ///
    /// The English source is "go back to `<relative phrase>`" rather than
    /// "since `<relative phrase>`": `relativeDescription` already reads as "N
    /// units ago", and English (and several other languages) double-mark the
    /// tense when a preposition meaning "since" is put directly in front of an
    /// "ago"-phrase.
    ///
    /// That does not mean every language's catalog entry reuses an English
    /// "go back to" shape — composing the actual sentence (19 hours / 3 days,
    /// substituted into each template) surfaced the same clash inside two of
    /// the six translations themselves:
    ///
    /// - **fr**: `l'historique remonte à %@` composed to `remonte à il y a 19
    ///   heures` — "à" stacked directly on "il y a" ("at" + "ago"), the same
    ///   mistake in French this comment used to claim French avoided. Fixed to
    ///   `l'historique commence %@` ("the log started `<phrase>`"), which
    ///   takes "il y a 19 heures" as a plain adverbial with no preposition in
    ///   front of it. The paired warning key (``annotation``'s
    ///   `records only go back to %@`) had the identical bug
    ///   (`ne remonte qu'à il y a 19 heures`) and is now the unrelated
    ///   construction `limite : %@` ("limit: `<phrase>`") — a colon-label
    ///   avoids the elision question a `que`-before-the-argument fix would
    ///   have raised (`que` vs `qu'` depends on whether the substituted phrase
    ///   starts with a vowel sound, which varies: "il y a…" does, but a
    ///   calendar-named result like "la semaine dernière" does not).
    /// - **ru**: `древнее %@ записей нет` composed to `древнее 19 часов назад
    ///   записей нет` — `древнее` ("older than") is a comparative that wants a
    ///   genitive noun, and "19 часов назад" is an adverbial "ago"-phrase, not
    ///   a noun in that case. Fixed to `самые старые записи — лишь %@` ("the
    ///   oldest records — only `<phrase>`"), reusing the neutral key's
    ///   dash-apposition (which has no case requirement) with `лишь` ("only")
    ///   added.
    ///
    /// The other four — **de** (`bis vor %@ zurück`, using the standalone "bis
    /// vor …" idiom, e.g. "bis vor Kurzem"), **es** (`hasta hace %@`, the same
    /// "hasta hace poco" shape), **ja** (`%@から…`, where relative phrases
    /// already end in "前" and "前から" is the ordinary way to say "since …
    /// ago"), and **zh-Hans** (`追溯到%@`, "traces back to `<phrase>`") — were
    /// each composed the same way (19 hours, 3 days) and read correctly by the
    /// same non-native reasoning that caught the fr/ru cases.
    ///
    /// **None of the six — including the two fixes above — has been checked by
    /// a native speaker.** Treat all six as 未验证 (unverified) beyond that
    /// reasoning; ru and fr are the two this comment can say were *wrong*
    /// before, not the two guaranteed right now.
    static func floorDescription(_ date: Date, relativeTo now: Date = Date()) -> String {
        String(localized: "records go back to \(relativeDescription(of: date, relativeTo: now))")
    }
}
