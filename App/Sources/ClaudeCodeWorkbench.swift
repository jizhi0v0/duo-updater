import SwiftUI
import AppKit
import DuoUpdaterCore

// The Claude Code group of the workbench's CLI tab: one row per install, and the
// detail pane a selected install opens. What the words say is decided in
// `ClaudeCodePresentation`; this file only lays them out.

private var homeDirectory: String { FileManager.default.homeDirectoryForCurrentUser.path }

// MARK: - Sidebar row

/// One Claude Code install in the CLI tab. The trailing control follows the rules
/// the user set: Update only when every gate passed (`oneClick`), the command to
/// copy when auto-update is off, and otherwise nothing — the caption says why.
struct ClaudeCodeSidebarRow: View {
    let status: ClaudeCodeStatus
    let cli: CLIToolsModel

    private var path: String { status.install.path }
    private var updating: Bool { cli.updating.contains(path) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: ClaudeCodePresentation.title(of: status.install, home: homeDirectory))
                    .font(.body).lineLimit(1).truncationMode(.middle)
                caption
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 2)
        .help(ClaudeCodePresentation.explanation(status) ?? path)
    }

    @ViewBuilder
    private var caption: some View {
        let installer = ClaudeCodePresentation.shortInstaller(status.install.method)
        if let error = cli.errors[path] {
            Text(verbatim: error).font(.caption).foregroundStyle(.red).lineLimit(1)
        } else if updating {
            // The update's own output ("Downloading…"), so it visibly moves, like a
            // formula upgrade's row.
            Text(verbatim: cli.progress[path] ?? String(localized: "Updating…"))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        } else if let version = cli.justUpdated[path] {
            // Sessions already open keep running the version they started with.
            Text("Updated to \(version) · restart open sessions")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if let warning = ClaudeCodePresentation.rowWarning(status) {
            Text(verbatim: warning).font(.caption).foregroundStyle(.orange).lineLimit(1)
        } else if status.state == .updateAvailable, let installed = status.install.version,
                  let latest = status.latestVersion {
            Text(verbatim: "\(installer) · \(installed) → \(latest)")
                .font(.caption).foregroundStyle(.tint).lineLimit(1)
        } else {
            Text(verbatim: [installer, status.install.version].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if updating {
            ProgressView().controlSize(.small)
        } else if status.oneClick != nil {
            Button("Update") { Task { await cli.update(path: path) } }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        } else if let command = ClaudeCodePresentation.manualCommand(status) {
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

// MARK: - Detail pane

/// A selected Claude Code install: where it is and what runs, the facts the
/// verdict was made from, why no update is offered when none is, the last failed
/// update's log, and the release notes between what it has and what its channel
/// has.
struct ClaudeCodeDetailPane: View {
    let status: ClaudeCodeStatus
    let cli: CLIToolsModel

    private var path: String { status.install.path }
    private var updating: Bool { cli.updating.contains(path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            facts
                .padding(16)
                .frame(maxWidth: 640, alignment: .topLeading)
            Divider()
            ClaudeCodeReleaseNotesView(installed: status.install.version, latest: status.latestVersion)
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
                Text(verbatim: "Claude Code").font(.title2).fontWeight(.semibold)
                Text(verbatim: location)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if updating {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: cli.progress[path] ?? String(localized: "Updating…"))
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            } else if status.oneClick != nil, let latest = status.latestVersion {
                Button("Update to \(latest)") { Task { await cli.update(path: path) } }
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
            if let log = cli.errorLogs[path] {
                GridRow {
                    label("Last update failed").foregroundStyle(.red)
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
                    .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Release notes

/// Claude Code's `CHANGELOG.md`, cut to what one install's reader wants
/// (`ClaudeCodeChangelog.relevant`) and drawn by the same view as every other
/// changelog, with their own version marked in the rail.
private struct ClaudeCodeReleaseNotesView: View {
    let installed: String?
    let latest: String?

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
            .task(id: "\(installed ?? "")|\(latest ?? "")") { await load(force: false) }
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
                Text("Claude Code’s changelog has no section for these versions yet.")
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
            let changelog = try await ClaudeCodeReleaseNotes.changelog(covering: latest, force: force)
            state = .loaded(ClaudeCodeChangelog.relevant(changelog, installed: installed, latest: latest))
        } catch ClaudeCodeReleaseNotes.Failure.http(let status) {
            state = .failed(String(localized: "GitHub answered HTTP \(status)."))
        } catch ClaudeCodeReleaseNotes.Failure.noSections {
            state = .failed(String(localized: "The file loaded but carried no release sections."))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// The whole changelog, fetched once and kept for the session: every install's
/// pane reads the same file (~860 KB, 407 sections on 2026-09-30), so switching
/// between installs should not fetch and parse it again.
@MainActor
enum ClaudeCodeReleaseNotes {
    enum Failure: Error {
        case http(Int)
        /// The file came back but no longer looks like a changelog — kept apart from
        /// a network failure so a format drift is not mistaken for a blip.
        case noSections
    }

    private static var cached: Changelog?

    /// The kept copy, unless it predates `latest` — the channel moved on since it
    /// was fetched, and the one section the reader most wants would be missing.
    static func changelog(covering latest: String?, force: Bool) async throws -> Changelog {
        if !force, let cached,
           latest.map({ latest in cached.entries.contains { $0.version == latest } }) ?? true {
            return cached
        }
        var request = URLRequest(url: ClaudeCodeChangelog.source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        // Off the main actor: 407 sections are tens of milliseconds of parsing (a
        // debug build measured 44 ms), which the window would otherwise stall for.
        let parsed = await Task.detached(priority: .userInitiated) {
            ClaudeCodeChangelog.parse(String(decoding: data, as: UTF8.self))
        }.value
        guard let parsed else { throw Failure.noSections }
        cached = parsed
        return parsed
    }
}
