import Foundation

/// Whether the CLI tab's Homebrew group is open, and what a click on its header
/// does to that.
///
/// The group starts closed, down to one header line: people almost always upgrade
/// Homebrew all at once from that header, and a hundred formula rows would push
/// every other tool's group out of sight. Open or closed is the user's choice and
/// is remembered (`preferenceExpanded`). Three things open it without touching
/// that choice, because each would otherwise hide what the user is looking at: a
/// search that matches rows inside, a selection that is one of its rows (a cask's
/// "Changelog" deep link lands on one), and a reveal (`revealing`, the popover's
/// "Show in Window" for unchecked packages). When they stop, the group goes back to
/// what the user chose.
///
/// Foundation only, so the app test target can compile it (see
/// `DuoUpdaterAppTests` in `App/project.yml`).
struct HomebrewGroupState: Equatable {
    /// The user's own choice, remembered across launches.
    var preferenceExpanded: Bool
    /// A deep link asked for the group's rows to be shown. For this window only,
    /// and spent by the next click on the header.
    var revealing = false

    /// Whether the group is drawn open.
    /// - Parameters:
    ///   - searchHits: a search is typed and matches at least one row inside.
    ///   - holdsSelection: the sidebar's selection is one of the group's rows.
    func isExpanded(searchHits: Bool, holdsSelection: Bool) -> Bool {
        preferenceExpanded || revealing || searchHits || holdsSelection
    }

    /// A click on the header, which is not offered while a search holds the group
    /// open. It turns over what is on screen, not the stored choice: a group a
    /// reveal opened closes on the first click, where flipping the choice would have
    /// opened it for good and left it open. Whatever it shows next becomes the
    /// user's choice, and the reveal is spent.
    ///
    /// Closing it while the selection is one of its rows is the caller's to
    /// resolve: that row is about to disappear, so the selection must leave it,
    /// or `holdsSelection` would hold the group open against the click.
    mutating func toggle(holdsSelection: Bool) {
        preferenceExpanded = !isExpanded(searchHits: false, holdsSelection: holdsSelection)
        revealing = false
    }
}
