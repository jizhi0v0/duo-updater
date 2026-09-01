import SwiftUI
import AppKit
import DuoUpdaterCore

/// A small coloured mark beside an app's name saying what it is built with —
/// Electron, Tauri, Qt, native, …
///
/// **These are our own marks, not vendor logos.** Two reasons, and the first is
/// not the legal one. A real brand logo is drawn for a website header: the
/// Electron mark, rendered at the 10pt this sits at, is a dark disc with hairline
/// orbits inside it — it brings its own background into the row and its detail is
/// the first thing to disappear. Drawn as one set, in one 16-unit box with one
/// stroke weight, nine marks read as a family and each survives the size it is
/// actually used at. The second reason is that it keeps Oracle's, Google's and The
/// Qt Company's trademarked artwork out of this repository.
///
/// Where a mark echoes the real one it is because the real one is already simple:
/// Electron *is* an atom, Qt *is* a Q in a square, Java *is* a steaming cup.
/// Tauri's is the one that resembles nothing in particular — its actual mark could
/// not be referenced when this was drawn, so it takes a hexagon and a core, the
/// crate-and-webview shape, rather than a bad guess at their artwork.
///
/// The three Apple-platform cases are device silhouettes and the cross-platform
/// runtimes are abstract shapes, which is itself a cue: a phone, a tablet with a
/// way out of it, a Mac.
struct RuntimeTag: View {
    let runtime: AppRuntime
    /// The bundle the mark belongs to, read only when its detail is opened — the
    /// runtime's own version lives inside it. Nil where there is no real app behind
    /// the mark.
    var bundle: URL?
    /// What the app's binary actually links, shown in the click-through detail for
    /// the cases where the runtime label alone is not the whole answer. Empty is
    /// normal — nothing is claimed when nothing was read.
    var frameworks: LinkedFrameworks = []
    /// Edge of the square the mark is drawn in. The default suits a list row; the
    /// workbench's detail header sets it larger to sit beside a `.title2` name.
    var size: CGFloat = 12
    /// Drawn on top of a selection highlight, which is blue — so the hue is
    /// dropped for the emphasized foreground the rest of a selected row already
    /// uses. Without this a blue `native` mark on a selected row is blue on blue
    /// and simply disappears; the same trap `ChannelTag` and the version line
    /// document for this list.
    var overHighlight: Bool = false
    /// Whether clicking the mark opens the explanation.
    ///
    /// On everywhere it can be, and off in the workbench's sidebar list: a button
    /// inside a `List` row eats the click that would otherwise select the row, so
    /// an interactive mark there would make a 12pt patch of every row refuse to
    /// select the app it belongs to.
    var interactive: Bool = true

    @State private var showingDetail = false
    @State private var version: String?
    /// Separate from `version` being nil, which is a real answer: Chromium,
    /// Flutter and the Apple-platform runtimes have no version worth printing, and
    /// a rebranded Electron framework can hide the one it has. Without this the nil
    /// answer is never remembered and every re-open pays for the search again.
    @State private var versionLoaded = false

    var body: some View {
        if interactive {
            Button { showingDetail = true } label: { mark }
                .buttonStyle(.borderless)
                .help(Self.clickHelp(runtime))
                .accessibilityLabel(Self.help(runtime))
                .popover(isPresented: $showingDetail, arrowEdge: .bottom) { detail }
                // A popover anchors to a point in the window, not to the row that
                // opened it — so once the list scrolls, it hangs over whatever has
                // slid into that spot, which here is the sticky search field. AppKit
                // closes a transient popover on an outside *click*, and a scroll is
                // not one.
                //
                // Watched from the mark's own frame rather than from the list's
                // scroll offset: the offset has to cross two view boundaries by
                // preference and environment to get here, and it did not survive the
                // trip. Its own geometry is a fact this view can see for itself, and
                // it works in any container — the workbench sidebar included.
                .background(
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.frame(in: .global).minY) {
                            showingDetail = false
                        }
                    }
                )
        } else {
            mark
                .help(Self.help(runtime))
                .accessibilityLabel(Self.help(runtime))
        }
    }

    private var mark: some View {
        RuntimeMark(runtime: runtime, size: size)
            .foregroundStyle(overHighlight
                             ? AnyShapeStyle(Color.white.opacity(0.92))
                             : AnyShapeStyle(Self.tint(runtime).opacity(Self.intensity)))
            // A 12pt glyph is a 12pt hit target. Padding the tappable area without
            // padding the drawing keeps the row's spacing while making the thing
            // clickable on the first try.
            .padding(3)
            .contentShape(Rectangle())
            .padding(-3)
    }

    /// The click-through explanation. Reached by clicking rather than only by
    /// hovering because a macOS tooltip waits out the system's own delay before it
    /// appears — long enough that the answer arrives after the question has been
    /// abandoned. The tooltip is still there for anyone who does hover.
    private var detail: some View {
        HStack(alignment: .top, spacing: 12) {
            RuntimeMark(runtime: runtime, size: 30)
                .foregroundStyle(Self.tint(runtime).opacity(Self.intensity))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.displayName(runtime)).font(.headline)
                    if let version {
                        Text(version)
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Self.help(runtime))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let linked = Self.linkedLine(runtime, frameworks) {
                    Text(linked)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .task {
            // Off the main thread and only once the detail is actually open: a
            // rebranded Electron framework is found by walking a binary, which is
            // fine for a single app someone asked about and would be indefensible
            // during a scan of the whole library. Tauri's walk is already paid for
            // — the scan had to do it to reach the verdict at all, and this reads
            // the same cached entry back out.
            guard !versionLoaded, let bundle else { return }
            version = await Task.detached(priority: .utility) {
                RuntimeVersion.read(runtime, bundleAt: bundle, scanningBinaries: true)
            }.value
            versionLoaded = true
        }
    }

    /// The width the mark claims, for a caller budgeting row space before layout.
    static func width(at size: CGFloat = 12) -> CGFloat { size }

    /// How much of the hue to actually paint.
    ///
    /// At full strength the marks won the row: a saturated blue laptop next to
    /// "Xcode" pulled the eye before the name did, which inverts what the row is
    /// for. Held against the row's own background at 12pt, 0.68 is where they stop
    /// competing with the name and still read as their colour — the value is a
    /// floor as much as a ceiling, since below about 0.55 the cyan and the green
    /// wash out on a light background, where opacity blends toward white rather
    /// than toward black.
    private static let intensity: Double = 0.68

    /// One hue per runtime, so a glance down the list separates them before any
    /// shape is read. The first cut was all-gray and the complaint was immediate:
    /// visible, but not noticeable.
    ///
    /// System colors rather than brand hex, because these have to survive both
    /// appearances — rendered on a 0.13 grey and on a 0.97 grey, hand-picked brand
    /// values either glare or wash out, while the system set is defined for both.
    /// Brand fidelity is followed where it survives that (Electron's teal, Qt's
    /// green, Flutter's light blue, Java's coffee) and dropped where it does not:
    /// Tauri's yellow is illegible on white, so it takes the orange next to it.
    ///
    /// Native is the one neutral, and it can afford to be: its mark is a solid
    /// Apple glyph, which carries at grey where a thin outline did not. That
    /// leaves blue where it belongs, on Chromium's own disc.
    static func tint(_ runtime: AppRuntime) -> Color {
        switch runtime {
        case .electron:  return .teal
        case .tauri:     return .orange
        case .flutter:   return .cyan
        case .qt:        return .green
        case .java:      return .brown
        case .chromium:  return .blue
        case .catalyst:  return .purple
        case .iOSApp:    return .indigo
        case .native:    return .gray
        }
    }

    /// What the runtime is called. Product names stay in Latin script in every
    /// language — they are what the vendor calls the thing, and a translated
    /// "Electron" would be a different word from the one in every document about
    /// it. Only the two that are descriptions rather than names get localized.
    static func displayName(_ runtime: AppRuntime) -> String {
        switch runtime {
        case .electron:  return "Electron"
        case .tauri:     return "Tauri"
        case .flutter:   return "Flutter"
        case .qt:        return "Qt"
        case .java:      return "Java"
        case .chromium:  return "Chromium"
        case .catalyst:  return "Mac Catalyst"
        case .iOSApp:    return String(localized: "iOS App", comment: "Runtime mark: an iPhone/iPad app running on Apple silicon")
        case .native:    return String(localized: "Native", comment: "Runtime mark: a native Mac app built with AppKit or SwiftUI")
        }
    }

    /// The hover text where the mark is clickable, following the pattern the other
    /// click-for-detail badges in the row use.
    static func clickHelp(_ runtime: AppRuntime) -> String {
        String(localized: "\(displayName(runtime)) — click for details")
    }

    /// The stand-in for the four runtimes that have no vendor mark. Nil for the
    /// rest, which draw their own artwork.
    static func symbol(_ runtime: AppRuntime) -> String? {
        switch runtime {
        case .java:      return "cup.and.saucer.fill"   // see RuntimeArtwork: no usable Java mark
        case .catalyst:  return "ipad.and.iphone"
        case .iOSApp:    return "iphone"
        case .native:    return "applelogo"  // Apple's own frameworks, Apple's own glyph
        case .electron, .tauri, .flutter, .qt, .chromium: return nil
        }
    }

    /// The frameworks line under the description, or nil where it would say
    /// nothing useful.
    ///
    /// Only for the two labels that genuinely under-describe an app. "Native"
    /// covers an AppKit app, an AppKit-plus-SwiftUI app and an app drawing every
    /// pixel itself on top of both — half the native apps on a normal machine link
    /// both frameworks, so the one-word label is the start of the answer rather
    /// than all of it. Catalyst gets it because UIKit is the interesting part.
    /// Everything else is already named by its runtime, and "Links AppKit" under
    /// "Electron" is true, unsurprising and pure noise.
    static func linkedLine(_ runtime: AppRuntime, _ frameworks: LinkedFrameworks) -> String? {
        guard runtime == .native || runtime == .catalyst else { return nil }
        let names = frameworks.names
        guard !names.isEmpty else { return nil }
        let list = ListFormatter.localizedString(byJoining: names)
        return String(localized: "Links \(list).", comment: "Detail line: which Apple frameworks the app's binary links")
    }

    /// The tooltip — and, since the mark has no text, the only place the name of
    /// the runtime appears when it is not clicked. Every sentence therefore has to
    /// say it.
    static func help(_ runtime: AppRuntime) -> String {
        switch runtime {
        case .electron:  return String(localized: "Built with Electron — it bundles its own copy of Chromium.")
        case .tauri:     return String(localized: "Built with Tauri — a Rust app drawing into the system WebView.")
        case .flutter:   return String(localized: "Built with Flutter.")
        case .qt:        return String(localized: "Built with Qt.")
        case .java:      return String(localized: "A Java app, shipping the runtime it needs.")
        case .chromium:  return String(localized: "Built on Chromium.")
        case .catalyst:  return String(localized: "An iPad app brought to the Mac with Mac Catalyst.")
        case .iOSApp:    return String(localized: "An iPhone or iPad app running on Apple silicon.")
        case .native:    return String(localized: "A native Mac app — built straight on Apple's frameworks, not a cross-platform runtime.")
        }
    }
}

/// Draws one runtime's mark: its own artwork where there is any, an SF Symbol
/// where there is not.
///
/// The vendor paths are parsed once and cached. Parsing is cheap, but this view
/// appears on every row of a list that rebuilds on every scan, and re-parsing a
/// 2.4KB path to draw a 12pt glyph a hundred times over is the kind of waste that
/// never announces itself.
private struct RuntimeMark: View {
    let runtime: AppRuntime
    let size: CGFloat

    private static let cache: [AppRuntime: Path] = {
        var paths: [AppRuntime: Path] = [:]
        for runtime in AppRuntime.allCases {
            guard let data = RuntimeArtwork.pathData(for: runtime),
                  let segments = SVGPath.parse(data) else { continue }
            var path = Path()
            for segment in segments {
                switch segment {
                case .move(let point):        path.move(to: point)
                case .line(let point):        path.addLine(to: point)
                case .curve(let to, let c1, let c2): path.addCurve(to: to, control1: c1, control2: c2)
                case .close:                  path.closeSubpath()
                }
            }
            paths[runtime] = path
        }
        return paths
    }()

    var body: some View {
        if runtime == .chromium {
            ChromiumDisc(size: size)
        } else if let path = Self.cache[runtime] {
            // Authored in a 24-unit box, and SVG's y-axis points down exactly as
            // SwiftUI's does, so this is a scale and nothing more. Filled with the
            // nonzero rule, which is what SVG defaults to and what the counters in
            // marks like Qt's rely on.
            path.applying(CGAffineTransform(scaleX: size / RuntimeArtwork.viewBox,
                                            y: size / RuntimeArtwork.viewBox))
                .fill(style: FillStyle(eoFill: false))
                .frame(width: size, height: size)
        } else if let symbol = RuntimeTag.symbol(runtime) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.95))
                .frame(width: size, height: size)
        }
    }
}


/// Chromium's disc: three segments around a hub, separated from it by a ring of
/// nothing.
///
/// Drawn rather than imported because there is no monochrome Chromium mark to
/// import — and nothing to get wrong by drawing it, since the logo *is* three arcs
/// and a circle. The three segments are one hue at three strengths: flattened to a
/// single tone the disc loses the thing that makes it recognizable, and painted in
/// Chrome's actual red/yellow/green it would claim to be Chrome, which most of
/// this bucket (Spotify, CapCut, anything embedding CEF) is not.
private struct ChromiumDisc: View {
    let size: CGFloat

    /// Degrees of blank between segments, the radius the segments stop at, the hub,
    /// and the three strengths — proportional so the mark holds together at 12pt
    /// and at 40.
    private static let gap: CGFloat = 7
    private static let innerRatio: CGFloat = 0.5
    private static let hubRatio: CGFloat = 0.42
    private static let tones: [Double] = [1.0, 0.72, 0.48]

    var body: some View {
        ZStack {
            ForEach(Array([90.0, 210.0, 330.0].enumerated()), id: \.offset) { index, start in
                sector(from: start + Self.gap, to: start + 120 - Self.gap)
                    .fill(.foreground.opacity(Self.tones[index]))
            }
            Circle()
                .fill(.foreground)
                .frame(width: size * Self.hubRatio, height: size * Self.hubRatio)
        }
        .frame(width: size, height: size)
    }

    private func sector(from: CGFloat, to: CGFloat) -> Path {
        var path = Path()
        let centre = CGPoint(x: size / 2, y: size / 2)
        path.addArc(center: centre, radius: size / 2,
                    startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        path.addArc(center: centre, radius: size / 2 * Self.innerRatio,
                    startAngle: .degrees(to), endAngle: .degrees(from), clockwise: true)
        path.closeSubpath()
        return path
    }
}
