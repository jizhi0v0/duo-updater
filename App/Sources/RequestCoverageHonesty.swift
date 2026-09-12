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
/// `RequestLogPane` calls ``annotation(since:floor:hasLoaded:now:locale:)``
/// once per `Range` case for the picker's menu labels, and
/// ``floorDescription(_:relativeTo:)`` for the caption and the status bar —
/// the same "how far back, in words" question, but the menu's answer has to
/// be short (it becomes the closed `Picker`'s own label — see
/// `annotation`'s doc) while the status bar's can be a full sentence, because
/// the status bar shows it unconditionally and the menu doesn't have to
/// repeat it.
enum RequestCoverageHonesty {
    /// What a range's menu row should say about the gap between what it
    /// promises and what the store can actually back it with, or `nil` when
    /// there is nothing to say.
    ///
    /// Deliberately short — the bare relative phrase ("19 hours ago"), not a
    /// sentence — because a `Picker`'s selected row becomes the label of the
    /// *closed* control: measured with `NSFont.systemFont(ofSize:
    /// NSFont.systemFontSize)`, "Last 7 days" is 68.5pt but "Last 7 days
    /// (records only go back to 19 hours ago)" is 306pt in English and over
    /// 400pt in German and Russian, wide enough to crowd the query field out
    /// of a 640pt-minimum window. The status bar already states the same
    /// fact as a full sentence unconditionally (``floorDescription(_:relativeTo:)``),
    /// so the menu only needs a short cue, not a repeat of the whole claim.
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
    ///   - hasLoaded: whether the log has been read at least once
    ///     (`RequestLogPane.hasLoaded`). `retainedFloor` is `nil` in two
    ///     situations that must not read the same way: an empty store, and
    ///     the pre-load window before `reloadRequestLog` has ever run (it
    ///     `await`s a flush and three queries against the whole store before
    ///     `retainedFloor` is set at all). Reporting the second one as "empty"
    ///     re-commits #460's own mistake — claiming something about the store
    ///     that is not actually known yet — for however long that `Task`
    ///     takes. `hasLoaded` defaults to `true` because every caller except
    ///     the one narrow pre-load window has already loaded.
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
    /// `floor == nil` *after loading* (the store holds no request events at
    /// all) is treated as *not* honouring any range that has a cutoff — fail
    /// closed, matching this repo's other "can't tell → don't claim it"
    /// rules — rather than as vacuously honouring every range. An empty store
    /// has kept nothing, so nothing it promises is backed by data.
    static func annotation(
        since: Date?, floor: Date?, hasLoaded: Bool = true, now: Date = Date(),
        locale: Locale = .current
    ) -> String? {
        guard let since else { return nil }
        guard hasLoaded else { return nil }
        guard let floor else {
            return String(localized: "nothing yet")
        }
        guard floor > since else { return nil }
        return relativeDescription(of: floor, relativeTo: now, locale: locale)
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

    /// The caption and status-bar phrasing — a full sentence, shown
    /// unconditionally (see ``annotation(since:floor:hasLoaded:now:locale:)``'s
    /// doc for why the menu does not repeat it).
    ///
    /// The English source is "go back to `<relative phrase>`" rather than
    /// "since `<relative phrase>`": `relativeDescription` already reads as "N
    /// units ago", and English (and several other languages) double-mark the
    /// tense when a preposition meaning "since" is put directly in front of an
    /// "ago"-phrase.
    ///
    /// That does not mean every language's catalog entry reuses an English
    /// "go back to" shape — composing the actual sentence (19 hours / 3 days,
    /// substituted into the template) surfaced the same clash in French:
    /// `l'historique remonte à %@` composed to `remonte à il y a 19 heures` —
    /// "à" stacked directly on "il y a" ("at" + "ago"), the same mistake in
    /// French this comment used to claim French avoided. Fixed to
    /// `l'historique commence %@` ("the log started `<phrase>`"), which takes
    /// "il y a 19 heures" as a plain adverbial with no preposition in front of
    /// it.
    ///
    /// The other five — **de** (`bis vor %@ zurück`, the standalone "bis
    /// vor …" idiom, e.g. "bis vor Kurzem"), **es** (`hasta hace %@`, the same
    /// "hasta hace poco" shape), **ja** (`%@から…`, where relative phrases
    /// already end in "前" and "前から" is the ordinary way to say "since …
    /// ago"), **ru** (`самые старые записи — %@`, dash-apposition, no
    /// preposition to clash), and **zh-Hans** (`追溯到%@`, "traces back to
    /// `<phrase>`") — were each composed the same way (19 hours, 3 days) and
    /// read correctly by the same non-native reasoning that caught the French
    /// case.
    ///
    /// **None of the six — including the French fix — has been checked by a
    /// native speaker.** Treat all six as 未验证 (unverified) beyond that
    /// reasoning; French is the one this comment can say was *wrong* before,
    /// not the one guaranteed right now.
    static func floorDescription(_ date: Date, relativeTo now: Date = Date()) -> String {
        String(localized: "records go back to \(relativeDescription(of: date, relativeTo: now))")
    }
}
