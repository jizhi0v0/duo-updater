import SwiftUI
import AppKit

/// The workbench's sidebar lists (Apps, CLI, Rollback): a lazily built scroll of
/// rows that draws its own selection.
///
/// **Why not `List(selection:)`.** With focus, a sidebar `List` paints its
/// selection as the solid accent fill, and nothing public changes that: a
/// `listRowBackground` is drawn under it and `tint(_:)` does not reach it (both
/// tried on the shipping window, 2026-10-10). The user found the fill too
/// saturated — and on it a tinted version line or an orange capsule could not be
/// read. This list draws one soft fill (`SidebarRowFill`) for the selected row,
/// with focus or without, and everything on it keeps its own colours.
///
/// What `List` did and this does instead:
/// - ↑/↓, Home/End and Page Up/Down move the selection among the selectable rows
///   (`order`, which leaves out headers, summary rows and closed groups) and
///   scroll it into view (`SidebarSelection`);
/// - a click selects; a button inside a row acts without selecting;
/// - the list takes the keyboard when clicked and by Tab, and draws no focus ring
///   round itself — the selection is the focus's mark, as a sidebar's is;
/// - each row is an accessibility element with its selected state, and the list
///   a labelled container.
///
/// Apps and CLI retain native section pinning to track the current section,
/// but draw its header in one fixed overlay so adjacent sections cannot push
/// the visible title up and down during fast scrolling.
struct SidebarList<Content: View, FocusValue: Hashable>: View {
    @Binding var selection: String?
    /// The selectable rows' ids in the order they are drawn: what the keys walk.
    let order: [String]
    /// The list's name for VoiceOver.
    let label: String
    /// Which of the window's lists holds the keyboard, and this list's value in it.
    /// One value per list rather than one flag for all: the workbench keeps a
    /// tab's list once built and only hides it, so several are alive at once.
    var focus: FocusState<FocusValue?>.Binding
    let focusValue: FocusValue
    /// The list is the one on screen. A hidden one is kept out of the key loop.
    var isShown = true
    @ViewBuilder var content: () -> Content

    @State private var viewportHeight: CGFloat = 0
    /// Only the displayed overlay can cover rows; later natural headers cannot.
    @State private var headerHeight: CGFloat = 0
    @State private var keyboardScroll = SidebarKeyboardScroll()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    content()
                }
                .padding(.bottom, 10)
            }
            // Let the sidebar show through the header without rows drawing
            // underneath its text as they scroll past.
            .mask {
                Rectangle().padding(.top, headerHeight)
            }
            .overlayPreferenceValue(SidebarHeaderAnchorsKey.self, alignment: .topLeading) { headers in
                GeometryReader { geometry in
                    let current = headers.last(where: { geometry[$0.bounds].minY <= 0.5 })
                        ?? headers.first(where: { $0.isInitial && geometry[$0.bounds].minY > 0.5 })
                    if let header = current {
                        header.content
                            .id("pinned:\(header.id)")
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .transaction { $0.disablesAnimations = true }
                    }
                }
            }
            .environment(\.sidebarSelectedRowFrame, { id, frame in
                guard keyboardScroll.target == id else { return }
                if headerHeight > 0, frame.minY < headerHeight - 0.5 {
                    keyboardScroll.target = nil
                    let anchor = UnitPoint(x: 0.5, y: min(1,
                        headerHeight / max(1, viewportHeight - frame.height)))
                    DispatchQueue.main.async {
                        guard selection == id else { return }
                        proxy.scrollTo(id, anchor: anchor)
                    }
                } else if frame.maxY <= viewportHeight + 0.5 {
                    keyboardScroll.target = nil
                }
            })
            .environment(\.sidebarScrollToHeader, { id in
                // Align the natural header before folding its rows, in the
                // same update, so the following section never flashes through.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                withTransaction(transaction) { proxy.scrollTo(id, anchor: .top) }
            })
            .coordinateSpace(name: SidebarSectionMetrics.coordinateSpace)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onPreferenceChange(SidebarHeaderHeightKey.self) { headerHeight = $0 }
            // `.edit`: focused by a click and by Tab, whatever the system's
            // keyboard-navigation setting — `.activate` alone would only take the
            // keyboard with that setting on, and the arrow keys would be dead.
            .focusable(isShown, interactions: .edit)
            .focused(focus, equals: focusValue)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .home, .end, .pageUp, .pageDown]) { press in
                guard let move = Self.move(for: press.key) else { return .ignored }
                let pageSize = SidebarSelection.pageSize(
                    viewportHeight: viewportHeight, rowHeight: SidebarRowMetrics.height)
                if let next = SidebarSelection.target(of: move, from: selection, in: order, pageSize: pageSize) {
                    keyboardScroll.target = next
                    selection = next
                    // No anchor: the least scroll that shows it, as a table scrolls
                    // to a selection made by key.
                    proxy.scrollTo(next)
                }
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    private static func move(for key: KeyEquivalent) -> SidebarMove? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .home: .home
        case .end: .end
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        default: nil
        }
    }
}

/// The sidebar `List`'s row geometry, kept so the rows look as they did: content
/// 16 pt from the column's edge and its selection 10 pt in, the selection the
/// row's full height (measured on a `.sidebar` List, 2026-10-10).
enum SidebarRowMetrics {
    static let selectionInset: CGFloat = 10
    static let contentInset: CGFloat = 6
    static let verticalPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 6
    /// A typical row's height — icon, name and caption — for the page keys' step.
    static let height: CGFloat = 42
}

enum SidebarSectionMetrics {
    static let coordinateSpace = "sidebar-scroll"
    static let verticalPadding: CGFloat = 10
    static let firstGap: CGFloat = 0
    static let betweenGap: CGFloat = 0
}

private struct SidebarHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SidebarHeaderAnchor {
    let id: String
    let isInitial: Bool
    let bounds: Anchor<CGRect>
    let content: AnyView
}

private struct SidebarHeaderAnchorsKey: PreferenceKey {
    static var defaultValue: [SidebarHeaderAnchor] { [] }
    static func reduce(value: inout [SidebarHeaderAnchor], nextValue: () -> [SidebarHeaderAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

@MainActor
private final class SidebarKeyboardScroll {
    var target: String?
}

private struct SidebarSelectedRowFrameKey: EnvironmentKey {
    static let defaultValue: @MainActor (String, CGRect) -> Void = { _, _ in }
}

private struct SidebarScrollToHeaderKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var sidebarSelectedRowFrame: @MainActor (String, CGRect) -> Void {
        get { self[SidebarSelectedRowFrameKey.self] }
        set { self[SidebarSelectedRowFrameKey.self] = newValue }
    }
    var sidebarScrollToHeader: @MainActor (String) -> Void {
        get { self[SidebarScrollToHeaderKey.self] }
        set { self[SidebarScrollToHeaderKey.self] = newValue }
    }
}

/// The selected row's fill, focused or not: the colour the user picked on the
/// shipping window — the sidebar `List`'s selection without focus, which is a
/// system fill, with the accent at 0.16 over it (2026-10-10).
///
/// Built from the same two parts rather than a fixed colour, so it follows the
/// appearance and the accent colour. `tertiarySystemFill` is the system fill
/// closest to that unfocused selection, sampled against it in the same window:
/// light 213,221,237 against 212,221,236; dark 67,79,99 against 71,83,102.
struct SidebarRowFill: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SidebarRowMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiarySystemFill))
            RoundedRectangle(cornerRadius: SidebarRowMetrics.cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
        }
    }
}

extension View {
    /// A selectable row of a `SidebarList`.
    func sidebarRow(_ id: String, selection: Binding<String?>) -> some View {
        modifier(SidebarRowModifier(id: id, selection: selection))
    }

    /// A row of a `SidebarList` that is not selectable — a group's summary — laid
    /// out like the others.
    func sidebarStaticRow() -> some View {
        padding(.horizontal, SidebarRowMetrics.contentInset)
            .padding(.vertical, SidebarRowMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SidebarRowMetrics.selectionInset)
    }

    /// The same height for app-source and CLI group headers, including those
    /// with no trailing action. The small action button sets their minimum.
    func sidebarGroupHeaderFrame() -> some View {
        ZStack(alignment: .trailing) {
            Button(String(localized: "Upgrade All")) {}
                .controlSize(.small)
                .buttonStyle(.bordered)
                .hidden()
                .frame(width: 0)
                .accessibilityHidden(true)
            self
        }
    }

    /// A section header of a `SidebarList`, placed as the sidebar `List`'s were
    /// (measured 2026-10-10): small, bold and secondary, starting 14 pt in and
    /// running to 2 pt from the edge — so a header's own trailing inset still lines
    /// it up with the rows. Pinned and inline headers use the same symmetric
    /// vertical padding, including when the sections are collapsed.
    func sidebarSectionHeader(id: String, isInitial: Bool = false) -> some View {
        SidebarSectionHeader(id: id, content: self, isInitial: isInitial)
    }
}

private struct SidebarSectionHeader<Content: View>: View {
    let id: String
    let content: Content
    var isInitial = false
    var isOverlay = false
    @State private var covered = false

    var body: some View {
        let header = content
            .sidebarGroupHeaderFrame()
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .padding(.vertical, SidebarSectionMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isOverlay {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SidebarHeaderHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
            .opacity(isOverlay || (!covered && !isInitial) ? 1 : 0)
            .allowsHitTesting(isOverlay || (!covered && !isInitial))
            .accessibilityHidden((covered || isInitial) && !isOverlay)
            .onGeometryChange(for: Bool.self) {
                $0.frame(in: .named(SidebarSectionMetrics.coordinateSpace)).minY <= 0.5
            } action: { covered = $0 }

        if isOverlay {
            header
        } else {
            header.anchorPreference(key: SidebarHeaderAnchorsKey.self, value: .bounds) { bounds in
                [SidebarHeaderAnchor(id: id, isInitial: isInitial, bounds: bounds, content: AnyView(
                    SidebarSectionHeader(id: id, content: content, isInitial: isInitial, isOverlay: true)))]
            }
        }
    }
}

private struct SidebarRowModifier: ViewModifier {
    let id: String
    @Binding var selection: String?
    @Environment(\.sidebarSelectedRowFrame) private var selectedRowFrame

    func body(content: Content) -> some View {
        let selected = selection == id
        content
            .padding(.horizontal, SidebarRowMetrics.contentInset)
            .padding(.vertical, SidebarRowMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if selected { SidebarRowFill() } }
            .contentShape(Rectangle())
            // A button inside the row takes its own click first, so Update acts
            // without selecting the row — as it did in the `List`.
            .onTapGesture { selection = id }
            .padding(.horizontal, SidebarRowMetrics.selectionInset)
            .id(id)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction { selection = id }
            .onGeometryChange(for: CGRect?.self) {
                selected ? $0.frame(in: .named(SidebarSectionMetrics.coordinateSpace)) : nil
            } action: { frame in
                if let frame { selectedRowFrame(id, frame) }
            }
    }
}
