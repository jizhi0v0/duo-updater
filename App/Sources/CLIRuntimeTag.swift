import SwiftUI
import Observation
import DuoUpdaterCore

/// What each CLI tool is built with, read off the main thread and kept for the
/// session — the CLI tab's counterpart of `InstalledApp.runtime`.
///
/// Its own store rather than more of `CLIToolsModel`: the verdict is a fact
/// about the file at a path, not about the tool's update check, and nothing
/// routes on it. `CLIRuntimeDetector` keeps each binary's verdict keyed by its
/// identity, so asking again after an update re-reads only what changed.
@MainActor
@Observable
final class CLIRuntimeStore {
    static let shared = CLIRuntimeStore()

    /// Path → reading, nil where the file proved nothing. A path is absent
    /// until its first read lands.
    private(set) var readings: [String: CLIRuntimeReading?] = [:]

    func reading(_ path: String) -> CLIRuntimeReading? { readings[path] ?? nil }

    /// Reads `path` again — a no-op read for an unchanged file, thanks to the
    /// detector's cache — and publishes the answer only when it changed.
    func load(_ path: String) async {
        let found = await offCooperativePool(qos: .utility) { CLIRuntimeDetector.read(path: path) }
        if readings[path] != .some(found) { readings[path] = found }
    }
}

/// A small coloured label beside a CLI tool's name saying what it is built
/// with — Go, Rust, Swift, Bun, … — drawn and behaving like `RuntimeTag` does
/// for an app: the runtime's hue at the same strength, white on a selected row,
/// a tooltip where it is not clickable and the explanation one click away where
/// it is.
///
/// Text rather than a mark. `RuntimeTag` draws a shape per runtime because an app
/// row has a name to sit beside and nine marks were drawn as one family; there is
/// no such set for languages, and a two-letter word reads at 9pt where a small
/// imitation of the Go gopher or the Rust gear would not.
struct CLIRuntimeTag: View {
    let reading: CLIRuntimeReading
    var overHighlight: Bool = false
    /// Whether clicking opens the explanation. Off in the sidebar, where a
    /// button inside a `List` row eats the click that selects the row.
    var interactive: Bool = true

    @State private var showingDetail = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if interactive {
            Button { showingDetail = true } label: { label }
                .buttonStyle(.borderless)
                .help(String(localized: "\(Self.title(reading)) — click for details"))
                .accessibilityLabel(Self.help(reading))
                .popover(isPresented: $showingDetail, arrowEdge: .bottom) { detail }
        } else {
            label
                .help(Self.help(reading))
                .accessibilityLabel(Self.help(reading))
        }
    }

    private var tint: Color { Self.tint(reading.runtime ?? reading.launcher) }

    /// The letters' colour. In the light appearance the system hues are drawn
    /// for fills, not for 9pt text on a pale capsule: cyan, green and orange
    /// read as washed out there (2026-10-10, the CLI tab in both appearances —
    /// Go's cyan was the faintest tag in the light list). A third of black mixed
    /// in brings them level with the dark appearance, where they read as is.
    private var textTint: Color {
        let tint = self.tint
        return colorScheme == .light ? tint.mix(with: .black, by: 0.3) : tint
    }

    private var label: some View {
        Text(verbatim: Self.title(reading))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(overHighlight ? Color.white.opacity(0.22) : tint.opacity(0.16)))
            .foregroundStyle(overHighlight
                             ? AnyShapeStyle(Color.white.opacity(0.92))
                             : AnyShapeStyle(textTint.opacity(Self.intensity)))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: Self.title(reading)).font(.headline)
            Text(Self.help(reading))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = reading.evidence {
                Text("Evidence: \(evidence.summary)",
                     comment: "Detail line: the Mach-O section, string or #! line a CLI tool's runtime was read from")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Text(verbatim: ClaudeCodePresentation.abbreviate(
                reading.binary, home: FileManager.default.homeDirectoryForCurrentUser.path))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    /// Stronger than `RuntimeTag`'s 0.68: that one paints a solid glyph, this one
    /// 9pt letters, which wash out on a light background at that strength.
    private static let intensity: Double = 0.85

    /// One hue per runtime, from the system set so both appearances hold, and
    /// following each language's own colour where one is free: Go's cyan,
    /// Rust's orange, Swift's red-orange as red, Node's green, Haskell's purple,
    /// Python's blue.
    ///
    /// Bun's own tan was tried as `.brown` and dropped: in the dark appearance
    /// it was clearly the faintest tag in the list (OpenCode's row, 2026-10-10),
    /// and the next hue toward it is Rust's orange, which Bun sits beside in the
    /// same list. Pink is far from every other hue here and reads in both.
    static func tint(_ runtime: CLIRuntime?) -> Color {
        switch runtime {
        case .go?:      .cyan
        case .rust?:    .orange
        case .swift?:   .red
        case .node?:    .green
        case .haskell?: .purple
        case .python?:  .blue
        case .bun?:     .pink
        case .deno?:    .indigo
        case .ruby?:    .mint
        case .perl?:    .teal
        case .shell?, nil: .gray
        }
    }

    /// The tag's words: `CLIRuntimeReading.title`, shared with `duo`.
    static func title(_ reading: CLIRuntimeReading) -> String { reading.title ?? "" }

    /// The tooltip and the detail's description: what the runtime means, then —
    /// for a launcher — what it does.
    static func help(_ reading: CLIRuntimeReading) -> String {
        var lines: [String] = []
        if let runtime = reading.runtime { lines.append(sentence(runtime)) }
        if reading.launcher != nil {
            lines.append(String(localized: "Started by a Node.js script that runs a native binary from the package’s platform package."))
            if reading.runtime == nil {
                lines.append(String(localized: "What that binary is built with couldn’t be determined."))
            }
        }
        return lines.joined(separator: " ")
    }

    static func sentence(_ runtime: CLIRuntime) -> String {
        switch runtime {
        case .bun:     String(localized: "Built on Bun — the Bun JavaScript runtime, or a program compiled into one executable with it.")
        case .deno:    String(localized: "Built with Deno — a program compiled into one executable with deno compile.")
        case .node:    String(localized: "Runs on Node.js.")
        case .go:      String(localized: "Written in Go.")
        case .swift:   String(localized: "Written in Swift.")
        case .haskell: String(localized: "Written in Haskell and compiled with GHC.")
        case .rust:    String(localized: "Written in Rust.")
        case .python:  String(localized: "Runs on Python.")
        case .shell:   String(localized: "A shell script.")
        case .ruby:    String(localized: "Runs on Ruby.")
        case .perl:    String(localized: "Runs on Perl.")
        }
    }
}

/// The tag for the install at `path`, once its reading has landed and only when
/// it says something; reads it whenever the path appears.
struct CLIRuntimeTagSlot: View {
    let path: String
    var overHighlight: Bool = false
    var interactive: Bool = true
    private var store: CLIRuntimeStore { .shared }

    var body: some View {
        // A ZStack with a zero-size placeholder rather than a bare `if`: a view
        // that resolves to nothing never appears, so its `.task` would never run
        // and the first reading would never be asked for.
        ZStack {
            if let reading = store.reading(path), reading.runtime != nil || reading.launcher != nil {
                CLIRuntimeTag(reading: reading, overHighlight: overHighlight, interactive: interactive)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: path) { await store.load(path) }
    }
}
