import Testing

/// When the CLI tab's Homebrew group is open, and what a click on its header
/// leaves remembered. Each case names the one-line mutation of
/// `HomebrewGroupState` it fails under.
struct HomebrewGroupStateTests {

    private static let closed = HomebrewGroupState(preferenceExpanded: false)

    @Test func closedByDefaultAndOpenWhenTheUserSaysSo() {
        #expect(!Self.closed.isExpanded(searchHits: false, holdsSelection: false))
        #expect(HomebrewGroupState(preferenceExpanded: true).isExpanded(searchHits: false, holdsSelection: false))
    }

    /// A search opens it and never writes the choice, so clearing the search closes
    /// it again. Mutation: dropping `searchHits` from `isExpanded`.
    @Test func aSearchOpensItOnlyWhileItMatches() {
        let group = Self.closed
        #expect(group.isExpanded(searchHits: true, holdsSelection: false))
        #expect(group.preferenceExpanded == false)
        #expect(!group.isExpanded(searchHits: false, holdsSelection: false))
    }

    /// A selected row keeps its group open: a cask's deep link lands on one, and a
    /// row picked during a search must not vanish when the search is cleared.
    /// Mutation: dropping `holdsSelection` from `isExpanded`.
    @Test func aSelectedRowKeepsItOpen() {
        #expect(Self.closed.isExpanded(searchHits: false, holdsSelection: true))
    }

    /// Mutation: dropping `revealing` from `isExpanded`.
    @Test func aRevealOpensItWithoutWritingTheChoice() {
        let group = HomebrewGroupState(preferenceExpanded: false, revealing: true)
        #expect(group.isExpanded(searchHits: false, holdsSelection: false))
        #expect(group.preferenceExpanded == false)
    }

    @Test func aClickOpensAClosedGroupAndRemembersIt() {
        var group = Self.closed
        group.toggle(holdsSelection: false)
        #expect(group.preferenceExpanded)
        #expect(group.isExpanded(searchHits: false, holdsSelection: false))
    }

    @Test func aClickClosesAnOpenGroupAndRemembersIt() {
        var group = HomebrewGroupState(preferenceExpanded: true)
        group.toggle(holdsSelection: false)
        #expect(!group.preferenceExpanded)
    }

    /// The click turns over what is on screen. A group a reveal opened closes on
    /// the first click, and the reveal is spent. Mutation: `preferenceExpanded.toggle()`
    /// opens it for good instead; not clearing `revealing` leaves it open.
    @Test func aClickClosesARevealedGroupAndSpendsTheReveal() {
        var group = HomebrewGroupState(preferenceExpanded: false, revealing: true)
        group.toggle(holdsSelection: false)
        #expect(!group.preferenceExpanded)
        #expect(!group.revealing)
        #expect(!group.isExpanded(searchHits: false, holdsSelection: false))
    }

    /// Open only because a row inside is selected: the click closes it (the caller
    /// then moves the selection out). Mutation: passing `holdsSelection: false` to
    /// `isExpanded` inside `toggle` opens it for good instead.
    @Test func aClickClosesAGroupHeldOpenBySelection() {
        var group = Self.closed
        group.toggle(holdsSelection: true)
        #expect(!group.preferenceExpanded)
    }
}
