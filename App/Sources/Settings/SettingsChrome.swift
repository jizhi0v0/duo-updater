import SwiftUI

/// Shared chrome for the Settings window: the page scaffold, the card, and the
/// row/control styling every pane is built from.
///
/// Cards sit on material rather than Liquid Glass — see `settingsCardBackground()`
/// for the opaque-window rendering bug that forces it. Glass survives where it
/// works: `.glassProminent` buttons. Every such decision lives in this file, so the
/// panes stay declarative — they say `SettingsCard { … }` and never mention it.

// MARK: - Metrics

enum SettingsMetrics {
    /// Corner radius of a card. Matches the concentric radius macOS 26 uses for
    /// grouped content inside a rounded window.
    static let cardRadius: CGFloat = 14
    /// Gap between cards.
    static let cardSpacing: CGFloat = 18
    /// Readable measure for a settings page. Wider windows pad, they don't stretch.
    static let contentWidth: CGFloat = 620
}

// MARK: - Page scaffold

/// One settings pane: a large title, a subtitle, then a stack of cards in a
/// scroll view. Panes provide only the cards.
struct SettingsPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            cards
                .frame(maxWidth: SettingsMetrics.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .softScrollEdges()
        .navigationTitle(section.label)
    }

    private var cards: some View {
        // No GlassEffectContainer: with cards on material there are no glassEffect
        // children left to merge, so it would be pure decoration. See
        // `settingsCardBackground()` for why glass is off here.
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            header
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.label)
                .font(.system(.title2, weight: .semibold))
            Text(section.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

}

// MARK: - Card

/// A titled group of rows on a slab — the unit a settings pane is built from.
/// `header` sits above the slab, `footer` below it, both outside it so long
/// explanatory text reads as text.
struct SettingsCard<Content: View>: View {
    var header: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    /// Footer as a view, for the rare case that needs a `Label` or a live warning
    /// rather than a static string.
    private var footerView: AnyView?

    init(header: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.footerView = nil
        self.content = content()
    }

    init(header: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> some View) {
        self.header = header
        self.footer = nil
        self.footerView = AnyView(footer())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(header)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCardBackground()

            if let footer {
                SettingsFootnote(footer)
            } else if let footerView {
                footerView
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Explanatory text under a card. Panes use this directly when a footnote needs
/// to sit outside any card.
struct SettingsFootnote: View {
    private let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

// MARK: - Divider

/// The separator between two rows inside a `SettingsCard`.
///
/// Not a bare `Divider()`: on a material card it's faint to the point of invisible,
/// and it bleeds to both card edges. A native grouped separator starts at the
/// label's leading edge (hence the inset matching `settingsRow()`'s horizontal
/// padding), runs to the trailing edge, and is a touch firmer than `Divider()`.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

// MARK: - Rows

extension View {
    /// Standard inset for one row inside a `SettingsCard`. Rows are separated by an
    /// explicit `SettingsDivider()` at the call site.
    func settingsRow() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The slab behind a card. **Deliberately material, not `glassEffect`.**
    ///
    /// Liquid Glass renders wrong inside an *opaque* window, verified on macOS 27.0
    /// beta (26A5378n): `content.glassEffect(…)` turns the content itself into glass
    /// and the card comes out an empty grey slab; `.background(Color.clear.glassEffect(…))`
    /// brings the content back but smears the whole card under the glass layer. Glass
    /// has nothing to sample behind an opaque window. (A transparent panel —
    /// `isOpaque = false`, clear background — is the case where it does work.)
    ///
    /// It's also the right call independently: Apple reserves Liquid Glass for
    /// floating/navigation layers, and System Settings uses material for grouped
    /// content. Glass stays where it works: `.glassProminent` buttons.
    ///
    /// If Apple fixes opaque-window compositing, come back via
    /// `Color.clear.glassEffect(.regular, in: shape)` — never `self.glassEffect(…)`.
    func settingsCardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
        return self
            .background(.thinMaterial, in: shape)
            .overlay { shape.strokeBorder(.separator.opacity(0.45), lineWidth: 0.5) }
    }

    /// macOS 26 fades scrolled content into the window edge instead of clipping it
    /// against the toolbar.
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

// MARK: - Buttons

extension View {
    /// A card's action button.
    ///
    /// Prominent gets Liquid Glass; non-prominent is always `.bordered` — not taste,
    /// but the same opaque-window bug as `settingsCardBackground()`: on macOS 27.0
    /// beta (26A5378n) `.buttonStyle(.glass)` swallows the label and leaves an empty
    /// grey capsule. `.glassProminent` is unaffected. Revert both together once the
    /// platform composites glass correctly in opaque windows.
    @ViewBuilder
    func settingsGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *), prominent {
            self.buttonStyle(.glassProminent)
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Sidebar icon tile

/// The rounded tinted square behind a sidebar symbol, as in System Settings.
struct SettingsIconTile: View {
    let section: SettingsSection
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(section.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: section.icon)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Small shared pieces

/// A label/value row: title on the left, arbitrary trailing content on the right.
/// `LabeledContent` in a non-`Form` context loses its alignment, so panes use this.
struct SettingsField<Trailing: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .settingsRow()
    }
}

/// Green check / orange warning / spinner — the status glyph shared by the
/// GitHub, Alcove, and Diagnostics panes.
struct SettingsStatusBadge: View {
    enum State { case loading, ok, warning, error }
    let state: State

    var body: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// Mask a secret for display: first 4 + dots + last 4. Short strings collapse to
/// a fixed dot run so length doesn't leak. Shared by the GitHub and Alcove panes.
func maskSecret(_ secret: String) -> String {
    guard secret.count > 12 else { return String(repeating: "•", count: 12) }
    return "\(secret.prefix(4))\(String(repeating: "•", count: 16))\(secret.suffix(4))"
}
