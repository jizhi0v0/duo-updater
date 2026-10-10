import Foundation

/// A key that moves a sidebar list's selection (`SidebarList`).
enum SidebarMove: Sendable, Equatable {
    case up, down, home, end, pageUp, pageDown
}

/// Where the workbench sidebars' keyboard moves the selection, apart from any
/// view so it can be tested: the lists draw their own selection
/// (`SidebarList`) rather than `List(selection:)`'s, and with it own what the
/// arrow keys do.
enum SidebarSelection {

    /// The row `move` selects, from `current`, among `order` — the selectable
    /// rows' ids in the order they are drawn, so section headers, summary rows and
    /// the rows of a closed group are never in it and never landed on.
    ///
    /// Clamped at both ends, the way a table's selection stops at its first and
    /// last row rather than wrapping. A selection that is not among `order` — none
    /// yet, or a row the search has hidden — starts from the nearer end: down,
    /// page down and Home go to the first row, up, page up and End to the last.
    /// Nil only when there is no row at all.
    static func target(of move: SidebarMove, from current: String?, in order: [String], pageSize: Int) -> String? {
        guard let first = order.first, let last = order.last else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            switch move {
            case .down, .pageDown, .home: return first
            case .up, .pageUp, .end: return last
            }
        }
        let page = max(1, pageSize)
        let target: Int
        switch move {
        case .up: target = index - 1
        case .down: target = index + 1
        case .pageUp: target = index - page
        case .pageDown: target = index + page
        case .home: target = 0
        case .end: target = order.count - 1
        }
        return order[min(max(target, 0), order.count - 1)]
    }

    /// How many rows a page key moves: the rows that fit in the visible height,
    /// less one, so the row the selection leaves stays in view — a table's page
    /// step. At least one.
    static func pageSize(viewportHeight: Double, rowHeight: Double) -> Int {
        guard rowHeight > 0, viewportHeight.isFinite else { return 1 }
        return max(1, Int(viewportHeight / rowHeight) - 1)
    }

    /// The CLI tab's selectable rows, in the order it draws them: the Homebrew
    /// group's rows while it is open, then the tool groups' while "Other tools" is
    /// open. A closed group's rows are not drawn, so they are not walked either.
    static func cliOrder(homebrewExpanded: Bool, homebrew: [String], otherToolsExpanded: Bool, tools: [String]) -> [String] {
        (homebrewExpanded ? homebrew : []) + (otherToolsExpanded ? tools : [])
    }
}
