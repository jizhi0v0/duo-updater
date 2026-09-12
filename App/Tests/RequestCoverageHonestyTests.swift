import Foundation
import Testing

/// #460: the Requests pane's range menu offered "Last 7 days" whether or not
/// the store had kept anything close to seven days, and the caption dropped
/// the only clue (the retention floor) the moment a range was picked. Every
/// case here is anchored to one of the mutations named in its comment; a case
/// that survives its own mutation is decoration, not a test.
struct RequestCoverageHonestyTests {

    // A fixed instant, not `Date()` — CLAUDE.md's rule against letting a
    // test's answer depend on the host clock. Every date below is built
    // relative to this one.
    private static let now = Date(timeIntervalSince1970: 1_757_640_000) // 2025-09-11T20:00:00Z
    private static let usLocale = Locale(identifier: "en_US_POSIX")

    private static func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }
    private static func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    // MARK: annotation — honoured ranges

    /// The store's floor reaches further back than the range asks for, so the
    /// range is honoured and gets no annotation.
    ///
    /// Mutation: flip the `floor > since` comparison (e.g. to `floor < since`
    /// or `floor >= since`) — this case would then wrongly grow a
    /// parenthetical on a range the store can fully back.
    @Test func aRangeTheStoreFullyCoversIsNotAnnotated() {
        let since = Self.daysAgo(7)          // "Last 7 days"
        let floor = Self.daysAgo(30)         // store goes back a month
        #expect(RequestCoverageHonesty.annotation(since: since, floor: floor, now: Self.now) == nil)
    }

    /// The boundary: the store's oldest event lands exactly on the range's
    /// cutoff. Treated as honoured (`floor > since` is false when they're
    /// equal), not as falling short by one instant.
    ///
    /// Mutation: `floor >= since` instead of `floor > since` — this exact
    /// case is the only one that tells the two apart.
    @Test func aFloorExactlyAtTheCutoffIsHonoured() {
        let since = Self.daysAgo(7)
        #expect(RequestCoverageHonesty.annotation(since: since, floor: since, now: Self.now) == nil)
    }

    // MARK: annotation — unhonoured ranges

    /// The store's floor is newer than the range's cutoff — exactly #460's
    /// reported case, a 19-hour-old store against "Last 7 days" — so the menu
    /// row must say so.
    ///
    /// Mutation: flip the `floor > since` comparison — this case would then
    /// wrongly report the range as honoured (`nil`).
    ///
    /// `locale: Self.usLocale` matters here specifically, unlike the nil/
    /// non-nil checks elsewhere in this file: this is the one assertion that
    /// inspects the *contents* of the note (`contains("19")`), and without a
    /// pinned locale `annotation` falls through to `Locale.current` — a host
    /// whose locale renders non-Western digits would fail this for a reason
    /// that has nothing to do with the code under test. CLAUDE.md's 2026-09-09
    /// rule: "would this test's answer change on another machine?" — before
    /// this parameter existed on `annotation`, the answer was yes.
    @Test func aRangeTheStoreCannotBackGetsAnnotated() {
        let since = Self.daysAgo(7)           // "Last 7 days"
        let floor = Self.hoursAgo(19)         // store only goes back 19 hours
        let note = RequestCoverageHonesty.annotation(since: since, floor: floor, now: Self.now, locale: Self.usLocale)
        // Exact match, not a substring check: the annotation is deliberately
        // short — just the bare relative phrase, no wrapping sentence — so
        // with the locale and clock both pinned there is exactly one correct
        // string (round 2 of #537's review: a `Picker`'s selected row becomes
        // its closed control's own label, and "records only go back to 19
        // hours ago" measured 306pt against 68.5pt for the plain label).
        #expect(note == "19 hours ago")
    }

    /// A "Last 30 days" cutoff against the same 19-hour floor must also be
    /// annotated — guards against a mutation that special-cases the largest
    /// range (`.month`) and leaves it unannotated while still annotating
    /// `.week`.
    ///
    /// Mutation: drop the annotation for the widest range only (an `if since
    /// != daysAgo(30)` guard slipped into the real function).
    @Test func theWidestRangeIsAnnotatedTooWhenUnhonoured() {
        let since = Self.daysAgo(30)          // "Last 30 days"
        let floor = Self.hoursAgo(19)
        #expect(RequestCoverageHonesty.annotation(since: since, floor: floor, now: Self.now) != nil)
    }

    // MARK: annotation — .all is never annotated

    /// `since: nil` stands for "All time", which promises nothing to fall
    /// short of — it must never get a parenthetical, no matter how young the
    /// store is.
    ///
    /// Mutation: return the annotation for `.all` (drop the `guard let since`
    /// early return).
    @Test func allTimeIsNeverAnnotated() {
        let floor = Self.hoursAgo(1)          // store is almost brand new
        #expect(RequestCoverageHonesty.annotation(since: nil, floor: floor, now: Self.now) == nil)
    }

    // MARK: annotation — empty store (loaded)

    /// An empty store (`floor == nil`) that HAS finished loading (`hasLoaded`
    /// defaults to `true` here) must NOT read as "everything is covered". It
    /// is the opposite: nothing has been kept, so no promise is backed by
    /// data, and every range with a cutoff must be annotated.
    ///
    /// Mutation: `guard let floor else { return nil }` instead of returning
    /// the "nothing yet" message — this case is the only one that tells
    /// "no annotation" and "empty-store annotation" apart, since both are
    /// non-crashing and the wrong one is silent.
    ///
    /// Contrast with ``theFirstLoadWindowIsNeverAnnotated()`` below: the same
    /// `floor: nil` input must answer differently depending on `hasLoaded` —
    /// that is exactly the distinction round 2 of #537's review asked for.
    @Test func anEmptyStoreIsNotTreatedAsFullyCovered() {
        let since = Self.daysAgo(7)
        #expect(RequestCoverageHonesty.annotation(since: since, floor: nil, now: Self.now) != nil)
    }

    /// `.all` still gets no annotation even against an empty store — the
    /// "no promise" rule and the "empty store" rule must compose, not race.
    @Test func allTimeIsNeverAnnotatedEvenWhenEmpty() {
        #expect(RequestCoverageHonesty.annotation(since: nil, floor: nil, now: Self.now) == nil)
    }

    // MARK: annotation — the pre-load window

    /// `retainedFloor` reads `nil` in the pre-load window too, not only for a
    /// truly empty store — `NetworkWindowView` renders the pane immediately
    /// and only then runs `reloadRequestLog`, which awaits a flush and three
    /// queries against the whole store before `retainedFloor` is ever set.
    /// A store holding 40,000 events must not be announced as "nothing yet"
    /// for however long that `Task` takes — which is exactly what happened
    /// before `hasLoaded` was threaded into `annotation` (round 2 of #537's
    /// review: "the fix re-commits the issue's own sin during the pre-load
    /// window").
    ///
    /// Mutation: drop the `guard hasLoaded else { return nil }` line (or
    /// default-ignore the parameter) — this case is the only one that tells
    /// "not loaded yet, say nothing" apart from "loaded and empty, say so":
    /// both take `floor: nil`, and the wrong answer is silent, not a crash.
    @Test func theFirstLoadWindowIsNeverAnnotated() {
        let since = Self.daysAgo(7)           // "Last 7 days"
        #expect(RequestCoverageHonesty.annotation(
            since: since, floor: nil, hasLoaded: false, now: Self.now
        ) == nil)
    }

    /// `.all` gets no annotation in the pre-load window either — the same
    /// "no promise, nothing to say" composition as
    /// ``allTimeIsNeverAnnotatedEvenWhenEmpty()``, one guard further out.
    @Test func allTimeIsNeverAnnotatedBeforeLoading() {
        #expect(RequestCoverageHonesty.annotation(
            since: nil, floor: nil, hasLoaded: false, now: Self.now
        ) == nil)
    }

    // MARK: relativeDescription

    /// The headline behaviour #460 asked for: a 19-hour gap reads as "19
    /// hours ago", not as a calendar month.
    ///
    /// Mutation: format with the deleted `MMMyyyy` template instead of
    /// `RelativeDateTimeFormatter` — the result would contain a month name
    /// ("September") and no "19".
    @Test func aNineteenHourFloorReadsAsHoursNotAMonth() {
        let floor = Self.hoursAgo(19)
        let text = RequestCoverageHonesty.relativeDescription(of: floor, relativeTo: Self.now, locale: Self.usLocale)
        #expect(text.contains("19"))
        #expect(!text.contains("September"))
    }

    /// A multi-day gap reads in days, exercising the other end of the unit
    /// range the formatter picks from.
    @Test func aThreeDayFloorReadsInDays() {
        let floor = Self.daysAgo(3)
        let text = RequestCoverageHonesty.relativeDescription(of: floor, relativeTo: Self.now, locale: Self.usLocale)
        #expect(text.contains("3"))
    }
}
