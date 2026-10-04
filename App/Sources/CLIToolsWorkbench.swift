import SwiftUI
import AppKit
import DuoUpdaterCore

// The tool groups of the workbench's CLI tab: one row per install, and the detail
// pane a selected install opens — Claude Code's own, or the one every other tool
// shares. What the words say is decided in `CLIToolPresentation` and
// `ClaudeCodePresentation`; this file only lays them out.

private var homeDirectory: String { FileManager.default.homeDirectoryForCurrentUser.path }

// MARK: - Sidebar row

/// One install of any tool in the CLI tab. The trailing control follows the rules
/// the user set: Update only when every gate passed (`oneClick`), the command to
/// copy when the tool's own auto-update is off, and otherwise nothing — the caption
/// says why.
struct CLIToolSidebarRow: View {
    let status: CLIToolStatus
    let cli: CLIToolsModel
    /// On the selection's accent fill a tinted caption is the fill's own colour
    /// and vanishes (seen on 2026-10-01: a selected bub row read as title only),
    /// so it turns white there, like the app and formula rows'.
    var isSelected = false

    private func emphasis(_ style: some ShapeStyle) -> AnyShapeStyle {
        isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(style)
    }

    private var id: CLIToolID { status.toolID }
    private var updating: Bool { cli.updating.contains(id) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: CLIToolPresentation.title(of: status, home: homeDirectory, among: cli.statuses))
                    .font(.body).lineLimit(1).truncationMode(.middle)
                caption
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 2)
        .help(CLIToolPresentation.explanation(status) ?? status.path)
    }

    @ViewBuilder
    private var caption: some View {
        if let error = cli.errors[id] {
            Text(verbatim: error).font(.caption).foregroundStyle(emphasis(.red)).lineLimit(1)
        } else if updating {
            // The update's own output ("Downloading…"), so it visibly moves, like a
            // formula upgrade's row.
            Text(verbatim: cli.progress[id] ?? String(localized: "Updating…"))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        } else if let version = cli.justUpdated[id] {
            Group {
                if status.kind == .claudeCode {
                    // Sessions already open keep running the version they started with.
                    Text("Updated to \(version) · restart open sessions")
                } else {
                    Text("Updated to \(version)")
                }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if let warning = CLIToolPresentation.rowWarning(status) {
            Text(verbatim: warning).font(.caption).foregroundStyle(emphasis(.orange)).lineLimit(1)
        } else {
            // Tinted when it is an update, like a formula row's `a → b`.
            Text(verbatim: CLIToolPresentation.versionCaption(status))
                .font(.caption)
                .foregroundStyle(status.state == .updateAvailable ? emphasis(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if updating {
            ProgressView().controlSize(.small)
        } else if status.oneClick != nil {
            Button("Update") { Task { await cli.update(id) } }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        } else if let command = CLIToolPresentation.manualCommand(status) {
            // A glyph, like the Brew trust command's row button: a labelled button
            // would leave a 260 pt sidebar too little room for the title beside it.
            CopyCommandButton(command: command)
        }
    }
}

// MARK: - Copy button

/// Copies a command and says so: ✓ for 1.5 s, then back to the copy glyph so a
/// second copy confirms again. The same confirm-and-revert as the Brew trust
/// command's button in `BrewUncheckedDetailPane`.
private struct CopyCommandButton: View {
    let command: String

    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copied = true
            copiedResetTask?.cancel()
            copiedResetTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            // One frame for both glyphs: the checkmark is shorter than doc.on.doc,
            // and the box resized when they swapped.
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Copy “\(command)”"))
        .accessibilityLabel(Text("Copy Command"))
    }
}

// MARK: - Shared pieces

/// The detail panes' running-update capsule: a spinner and the update's own
/// latest line.
private struct UpdateProgressCapsule: View {
    let line: String?

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(verbatim: line ?? String(localized: "Updating…"))
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}

/// A failed update's whole output, under its label in a facts grid.
private struct FailedUpdateLogRow: View {
    let log: String

    var body: some View {
        GridRow {
            // The panes' `label` chain, kept as it was when it lived in them.
            Text("Last update failed")
                .foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                .foregroundStyle(.red)
            ScrollView {
                Text(verbatim: log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Claude Code's detail pane

/// A selected Claude Code install: where it is and what runs, the facts the
/// verdict was made from, why no update is offered when none is, the last failed
/// update's log, and the release notes between what it has and what its channel
/// has.
struct ClaudeCodeDetailPane: View {
    let status: ClaudeCodeStatus
    let cli: CLIToolsModel

    private var path: String { status.install.path }
    private var id: CLIToolID { CLIToolID(kind: .claudeCode, path: path) }
    private var updating: Bool { cli.updating.contains(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            facts
                .padding(16)
                .frame(maxWidth: 640, alignment: .topLeading)
            Divider()
            // The shared status of the same install: the release notes are asked
            // for by it, like every other tool's.
            if let shared = cli.status(CLIToolID(kind: .claudeCode, path: status.install.path)) {
                CLIToolReleaseNotesView(status: shared, cli: cli)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CLIToolKind.claudeCode.displayName).font(.title2).fontWeight(.semibold)
                Text(verbatim: location)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if updating {
                UpdateProgressCapsule(line: cli.progress[id])
            } else if status.oneClick != nil, let latest = status.latestVersion {
                Button("Update to \(latest)") { Task { await cli.update(id) } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    /// The install's path, and the file that actually runs when it is another one
    /// (a native launcher's `versions/` target, an npm package's binary).
    private var location: String {
        let shown = ClaudeCodePresentation.abbreviate(path, home: homeDirectory)
        guard let executable = status.install.executable, executable != path else { return shown }
        return "\(shown) → \(ClaudeCodePresentation.abbreviate(executable, home: homeDirectory))"
    }

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                label("Installed by")
                Text(verbatim: installedBy)
            }
            GridRow {
                label("Version")
                versionValue
            }
            GridRow {
                label("Signature")
                Text(verbatim: signature)
            }
            GridRow {
                label("Channel")
                Text(verbatim: channel)
            }
            GridRow {
                label("Update")
                updateValue
            }
            if let log = cli.errorLogs[id] {
                FailedUpdateLogRow(log: log)
            }
        }
        .textSelection(.enabled)
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private var installedBy: String {
        let installer = ClaudeCodePresentation.installer(status.install.method)
        // An npm copy is updated by the npm of the node prefix it lives in, so the
        // prefix is part of the answer.
        guard let prefix = status.install.nodePrefix else { return installer }
        return "\(installer) · \(ClaudeCodePresentation.abbreviate(prefix, home: homeDirectory))"
    }

    /// "Matches", never "matches the signed manifest": the vendor does publish a
    /// `manifest.json.sig`, but `ClaudeCodeRelease` reads only the JSON, and the
    /// comparison is by size (`ClaudeCodeRelease.sizeMatches`).
    @ViewBuilder
    private var versionValue: some View {
        if let version = status.install.version {
            switch status.versionConfirmed {
            case true?:
                Text("\(version) · matches Anthropic’s release manifest")
            case false?:
                Text("\(version) · doesn’t match Anthropic’s release manifest").foregroundStyle(.orange)
            case nil:
                Text("\(version) · not checked against a release manifest")
            }
        } else {
            Text("Can’t be read").foregroundStyle(.orange)
        }
    }

    private var signature: String {
        switch status.install.signature {
        case .anthropic?: String(localized: "Anthropic (Team \(ClaudeCodeScanner.teamIdentifier))")
        case .otherSigner?: String(localized: "Signed, but not by Anthropic")
        case .invalid?: String(localized: "Unsigned or damaged")
        case nil: String(localized: "Not checked")
        }
    }

    private var channel: String {
        let name = status.channel.rawValue
        guard let latest = status.latestVersion else {
            // No latest also when the check stopped before asking (a broken copy,
            // not Anthropic's, no version): then it was not read, not unreadable.
            return status.withheld == .channelUnreadable ? String(localized: "\(name) → couldn’t be read") : name
        }
        return "\(name) → \(latest)"
    }

    @ViewBuilder
    private var updateValue: some View {
        if let command = status.oneClick {
            // Exactly what the Update button runs, so nothing about it is a surprise.
            Text(verbatim: command.display)
                .font(.system(.body, design: .monospaced))
        } else if let explanation = ClaudeCodePresentation.explanation(status) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: explanation)
                if let command = ClaudeCodePresentation.manualCommand(status) {
                    Text("To update it yourself, run:")
                    HStack(spacing: 8) {
                        Text(verbatim: command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        CopyCommandButton(command: command)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        } else if status.state == .ahead {
            Text("Newer than the channel’s latest")
        } else {
            Text("Up to date")
        }
    }
}

// MARK: - Every other tool's detail pane

/// A selected install of a tool without a pane of its own (every tool but Claude
/// Code): built from `CLIToolStatus`'s shared fields — where it is, what it reads
/// as against what its channel has, the facts its tool's payload adds
/// (`CLIToolPresentation.facts`), what the Update button runs or why there is
/// none, the last failed update's log, and the release notes in between.
struct CLIToolDetailPane: View {
    let status: CLIToolStatus
    let cli: CLIToolsModel

    private var id: CLIToolID { status.toolID }
    private var updating: Bool { cli.updating.contains(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            facts
                .padding(16)
                .frame(maxWidth: 640, alignment: .topLeading)
            Divider()
            CLIToolReleaseNotesView(status: status, cli: cli)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                // "rustup", an npm package's name: the install's own name when the
                // tool's group holds several kinds of thing. The path says which.
                Text(verbatim: status.name ?? status.kind.displayName).font(.title2).fontWeight(.semibold)
                Text(verbatim: ClaudeCodePresentation.abbreviate(status.path, home: homeDirectory))
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if updating {
                UpdateProgressCapsule(line: cli.progress[id])
            } else if status.oneClick != nil, let latest = status.latestVersion {
                Button("Update to \(latest)") { Task { await cli.update(id) } }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                label("Version")
                if let version = status.installedVersion {
                    Text(verbatim: version)
                } else {
                    Text("Can’t be read").foregroundStyle(.orange)
                }
            }
            GridRow {
                // A tool without channels has one line of releases: its latest.
                if status.channel == nil { label("Latest") } else { label("Channel") }
                Text(verbatim: latest)
            }
            // The tool's own: signature, how it got there, what else the verdict
            // rests on (`CLIToolPresentation.facts`).
            ForEach(CLIToolPresentation.facts(of: status, home: homeDirectory), id: \.label) { fact in
                GridRow {
                    Text(verbatim: fact.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    // No `fixedSize(vertical:)` on any text of this pane: the window's
                    // `.contentMinSize` measures it at a near-zero width, where a
                    // fixed-size paragraph wraps a character a line — uv's facts
                    // pushed the workbench's minimum height to 3857 pt, off the
                    // bottom of the screen (2026-10-02; the Rollback notice did the
                    // same in September). Unfixed, the text still wraps in full.
                    Text(verbatim: fact.value)
                }
            }
            GridRow {
                label("Update")
                updateValue
            }
            if let log = cli.errorLogs[id] {
                FailedUpdateLogRow(log: log)
            }
        }
        .textSelection(.enabled)
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    /// "stable → 0.5.0", or the version alone for a tool without channels. Not
    /// read is not unreadable: only `channelUnreadable` says the asking failed.
    private var latest: String {
        let unreadable = status.withheld == .channelUnreadable
        switch (status.channel, status.latestVersion) {
        case (let channel?, let latest?): return "\(channel) → \(latest)"
        case (let channel?, nil):
            return unreadable ? String(localized: "\(channel) → couldn’t be read") : channel
        case (nil, let latest?): return latest
        case (nil, nil): return unreadable ? String(localized: "Can’t be read") : String(localized: "Not checked")
        }
    }

    @ViewBuilder
    private var updateValue: some View {
        if let command = status.oneClick {
            VStack(alignment: .leading, spacing: 6) {
                // Exactly what the Update button runs, so nothing about it is a surprise.
                Text(verbatim: command.display)
                    .font(.system(.body, design: .monospaced))
                if let caution = CLIToolPresentation.caution(status) {
                    Text(verbatim: caution)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let explanation = CLIToolPresentation.explanation(status) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: explanation)
                if let command = CLIToolPresentation.manualCommand(status) {
                    Text("To update it yourself, run:")
                    HStack(spacing: 8) {
                        Text(verbatim: command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        CopyCommandButton(command: command)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        } else if status.state == .ahead {
            Text("Newer than the channel’s latest")
        } else {
            Text("Up to date")
        }
    }
}

// MARK: - Release notes

/// A tool's release notes from its provider, cut to what one install's reader
/// wants (`CLIToolChangelog.relevant`) and drawn by the same view as every other
/// changelog, with their own version marked in the rail. The fetched document is
/// kept for the session by `CLIToolsModel.releaseNotes`.
private struct CLIToolReleaseNotesView: View {
    let status: CLIToolStatus
    let cli: CLIToolsModel

    private var kind: CLIToolKind { status.kind }
    private var installed: String? { status.installedVersion }
    private var latest: String? { status.latestVersion }

    private enum LoadState {
        case loading
        case loaded(Changelog?)
        case failed(String)
    }
    @State private var state: LoadState = .loading

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keyed on both versions: a refresh that finds a newer latest, or an
            // update that moves the installed one, re-cuts the notes.
            .task(id: "\(status.releaseNotesKey)|\(installed ?? "")|\(latest ?? "")") { await load(force: false) }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded(let changelog?):
            ChangelogEntriesView(changelog: changelog, runningVersion: installed)
        case .loaded(nil):
            ContentUnavailableView {
                Label("No release notes", systemImage: "doc.text.magnifyingglass")
            } description: {
                if kind == .boat {
                    // Boat's releases carry no notes at all (`BoatProvider`).
                    Text("\(kind.displayName) publishes no release notes.")
                } else if case .bun = status.detail {
                    // bun's releases carry install commands; its notes are blog posts.
                    Text("Bun publishes its release notes on its blog, not with its releases.")
                } else {
                    Text("\(kind.displayName)’s release notes have no section for these versions yet.")
                }
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Couldn't load the release notes")
                    .font(.callout)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("Try Again") { Task { await load(force: true) } }
                    .font(.callout)
            }
        }
    }

    private func load(force: Bool) async {
        if force { state = .loading }
        do {
            let changelog = try await cli.releaseNotes(for: status, force: force)
            state = .loaded(CLIToolChangelog.relevant(changelog, installed: installed, latest: latest))
        } catch CLIToolReleaseNotesError.http(let status) {
            state = .failed(String(localized: "The server answered HTTP \(status)."))
        } catch CLIToolReleaseNotesError.noSections {
            state = .failed(String(localized: "The file loaded but carried no release sections."))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
