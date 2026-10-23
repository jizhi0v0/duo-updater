import SwiftUI
import AppKit

/// The native macOS search field (`NSSearchField`) — same control SwiftUI's
/// `.searchable` uses, so it looks like the field we started with — but with its
/// "recent searches" menu fully disabled. That recents menu is what flashed an empty
/// dropdown on first focus; wrapping AppKit directly lets us turn it off while keeping
/// the standard rounded search-field appearance, magnifier, and built-in clear button.
struct AppSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String = String(localized: "Search apps")

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        // Kill the recents menu — data, template, and autosave — so first focus
        // never flashes an empty "No Recent Searches" dropdown.
        field.recentsAutosaveName = nil
        field.searchMenuTemplate = nil
        if let cell = field.cell as? NSSearchFieldCell {
            cell.maximumRecents = 0
            cell.searchMenuTemplate = nil
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        // The popover's field edits the apps' search or the tool groups' page's,
        // a different binding on each side: typing must reach the current one.
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        // The popover's one field searches the apps or, on the tool groups'
        // page, the groups: the same field, so its prompt follows.
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
