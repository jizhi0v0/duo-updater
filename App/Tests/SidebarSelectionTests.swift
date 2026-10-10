import Testing

/// Where the workbench sidebars' keys move the selection (`SidebarSelection`).
///
/// Each case names the one-line mutation of `SidebarSelection` it fails under.
struct SidebarSelectionTests {

    private let order = ["a", "b", "c", "d", "e", "f"]

    private func move(_ move: SidebarMove, from current: String?, page: Int = 2) -> String? {
        SidebarSelection.target(of: move, from: current, in: order, pageSize: page)
    }

    /// Mutations: swap the `.up`/`.down` offsets; drop the `- 1` or `+ 1`.
    @Test func arrowsStepOneRow() {
        #expect(move(.down, from: "c") == "d")
        #expect(move(.up, from: "c") == "b")
    }

    /// The ends hold: no wrap-around, no running off the list.
    ///
    /// Mutation: remove the `min(max(…))` clamp.
    @Test func arrowsAndPagesClampAtTheEnds() {
        #expect(move(.down, from: "f") == "f")
        #expect(move(.up, from: "a") == "a")
        #expect(move(.pageDown, from: "e") == "f")
        #expect(move(.pageUp, from: "b") == "a")
    }

    /// Mutations: page by one row; swap the page directions.
    @Test func pageKeysMoveAPage() {
        #expect(move(.pageDown, from: "a", page: 3) == "d")
        #expect(move(.pageUp, from: "f", page: 3) == "c")
    }

    /// Mutation: drop the `max(1, …)` guard — a zero page would not move.
    @Test func aPageIsAtLeastOneRow() {
        #expect(move(.pageDown, from: "a", page: 0) == "b")
        #expect(SidebarSelection.pageSize(viewportHeight: 20, rowHeight: 42) == 1)
        #expect(SidebarSelection.pageSize(viewportHeight: 420, rowHeight: 42) == 9)
    }

    /// Mutations: Home to the last row; End to the first.
    @Test func homeAndEndGoToTheEnds() {
        #expect(move(.home, from: "d") == "a")
        #expect(move(.end, from: "b") == "f")
    }

    /// No selection yet, or one the search has hidden: down starts at the top, up
    /// at the bottom.
    ///
    /// Mutation: start every move from the first row.
    @Test func aSelectionOutsideTheListStartsFromTheNearerEnd() {
        #expect(move(.down, from: nil) == "a")
        #expect(move(.up, from: nil) == "f")
        #expect(move(.down, from: "hidden-by-search") == "a")
        #expect(move(.end, from: "hidden-by-search") == "f")
    }

    /// A search narrows the list; the selection it keeps moves among what is left,
    /// skipping the rows it hid.
    @Test func aSelectionSurvivesAFilter() {
        let filtered = ["b", "d", "f"]
        #expect(SidebarSelection.target(of: .down, from: "d", in: filtered, pageSize: 1) == "f")
        #expect(SidebarSelection.target(of: .up, from: "d", in: filtered, pageSize: 1) == "b")
    }

    @Test func anEmptyListSelectsNothing() {
        #expect(SidebarSelection.target(of: .down, from: "a", in: [], pageSize: 1) == nil)
    }

    /// Headers and closed groups are not rows to land on: the CLI tab's order
    /// leaves out a closed group's rows, and the keys walk straight from the last
    /// Homebrew row to the first tool row.
    ///
    /// Mutations: keep a closed Homebrew group's rows; keep closed tool groups'.
    @Test func theCLIOrderSkipsClosedGroups() {
        let brew = ["brew:formula:a", "brew:formula:b"], tools = ["tool:x", "tool:y"]
        #expect(SidebarSelection.cliOrder(homebrewExpanded: true, homebrew: brew, otherToolsExpanded: true, tools: tools)
            == brew + tools)
        #expect(SidebarSelection.cliOrder(homebrewExpanded: false, homebrew: brew, otherToolsExpanded: true, tools: tools)
            == tools)
        #expect(SidebarSelection.cliOrder(homebrewExpanded: true, homebrew: brew, otherToolsExpanded: false, tools: tools)
            == brew)
        let order = SidebarSelection.cliOrder(homebrewExpanded: true, homebrew: brew, otherToolsExpanded: true, tools: tools)
        #expect(SidebarSelection.target(of: .down, from: "brew:formula:b", in: order, pageSize: 1) == "tool:x")
    }
}
