import AppKit
import DuoUpdaterCore
import SwiftUI

private typealias GitSource = PersonalGitHubSource

private extension PersonalGitHubSource.Track {
    var title: String {
        switch self {
        case .stable: String(localized: "Stable")
        case .preview: String(localized: "Preview")
        case .nightly: String(localized: "Nightly")
        }
    }
}

private extension PersonalGitHubSource.Release.TagIssue {
    var explanation: String {
        switch self {
        case .unrecognized: String(localized: "This tag has no comparable version.")
        case .previewFlagOnStableTag: String(localized: "GitHub marks this as a prerelease, but the tag has no prerelease identifier.")
        case .stableFlagOnPreviewTag: String(localized: "The tag identifies a prerelease. GitHub’s prerelease flag is off.")
        }
    }
}

private struct SourceGitHubSettingsButton: View {
    let model: AppListModel
    @Environment(\.openWindow) private var openWindow
    @State private var request = UUID()

    var body: some View {
        Button("Open Settings") {
            model.personalSourceSettingsOrigin = NSApp.keyWindow
            model.personalSourceSettingsRequest = request
            model.requestedSettingsSection = .github
            model.requestedSettingsAnchor = .githubCLI
            openWindow(id: SettingsView.windowID)
            model.surfaceWindow(sceneID: SettingsView.windowID)
        }
        .onDisappear {
            if model.personalSourceSettingsRequest == request {
                model.personalSourceSettingsRequest = nil
                model.personalSourceSettingsOrigin = nil
            }
        }
    }
}

struct PersonalSourcePanel: View {
    let result: UpdateResult
    let model: AppListModel
    @State private var editor = false
    @State private var selected: Int64?
    private let store = PersonalSources.shared
    private var path: String { result.app.path.path }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                if let record = store.record(path) {
                    Label(record.repository.full_name, systemImage: "link")
                    Text(record.track.title).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(result.app) } }
                    Button("Edit Source…") { editor = true }
                } else if store.records[path] != nil {
                    Text("Unsupported source configuration. Subscription paused.")
                } else {
                    Button("Add GitHub Source…", systemImage: "plus") { editor = true }
                }
            }
            if let message = store.messages[path] { Text(verbatim: message).font(.callout).textSelection(.enabled) }
            if store.anonymousLimited.contains(path) { SourceGitHubSettingsButton(model: model).id(path) }
            if let snapshot = store.snapshots[path], let record = store.record(path) {
                if !model.acceptsPersonalSource(result) {
                    Text("Tracking releases. The app’s existing update route takes priority.").foregroundStyle(.secondary)
                }
                let matches = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable)
                if let release = matches.first {
                    if let candidate = store.candidate(result) {
                        if model.acceptsPersonalSource(result), store.messages[path] == nil {
                            switch store.action(for: candidate, path: path, record: record) {
                            case .page(let reason): Text(reason).foregroundStyle(.secondary)
                            case .verify: Text("Package not yet verified. Choose Update to download and check a package.").foregroundStyle(.secondary)
                            case .blocked: Text("Blocked").foregroundStyle(.red)
                            case .reveal: EmptyView()
                            }
                        }
                        Text(verbatim: (result.app.shortVersion ?? "?") + " → " + release.tag_name)
                            .font(.callout.bold())
                    }
                    let assets = release.assets.filter { $0.matchesMac && $0.matches(filename: record.filenameContains) }
                    if assets.isEmpty {
                        Text("No compatible package matched the filename filter. Use the release page.")
                    } else {
                        Text(verbatim: assets.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
                            .lineLimit(2).help("Platform and architecture are estimated from the filename.")
                    }
                }
                if matches.isEmpty { Text(snapshot.truncated ? "No matching release in the latest 60 releases." : "No comparable release on this track.") }
                if !snapshot.releases.isEmpty {
                    let selectedRelease = snapshot.releases.first { $0.id == selected } ?? matches.first ?? snapshot.releases[0]
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(snapshot.releases) { release in
                                    Button {
                                        selected = release.id
                                    } label: {
                                        Text(verbatim: release.tag_name)
                                            .lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(5)
                                            .background(selectedRelease.id == release.id ? Color.accentColor.opacity(0.16) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(selectedRelease.id == release.id ? .isSelected : [])
                                }
                            }
                        }.frame(width: 110).accessibilityLabel("Release history")
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(verbatim: selectedRelease.tag_name).bold()
                                Spacer()
                                if let url = GitSource.page(repository: snapshot.repository, release: selectedRelease) {
                                    Link("Open release page", destination: url)
                                }
                            }
                            if let issue = selectedRelease.tagIssue {
                                Label(issue.explanation, systemImage: "info.circle").foregroundStyle(.secondary)
                            }
                            ScrollView {
                                Text(verbatim: selectedRelease.body.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "No release notes."))
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: model.acceptsPersonalSource(result) ? .infinity : 160)
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .sheet(isPresented: $editor) { PersonalSourceEditor(result: result, model: model) }
        .task(id: path) { if store.snapshots[path] == nil { await store.refresh(result.app) } }
    }
}

struct PersonalSourceAction: View {
    let result: UpdateResult
    let model: AppListModel
    private let store = PersonalSources.shared
    private var path: String { result.app.path.path }
    var body: some View {
        if let release = store.candidate(result) {
            releaseAction(release)
        } else if store.busy.contains(path) {
            ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub source")
        } else if store.record(path)?.handoff != nil {
            Button("Show current installation") { NSWorkspace.shared.activateFileViewerSelecting([result.app.path]) }
                .help(store.messages[path] ?? "")
        } else if let record = store.record(path), let snapshot = store.snapshots[path], !store.paused.contains(path) {
            let matches = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable)
            if let latest = matches.first, let version = GitSource.Version(latest.tag_name), version == GitSource.Version(record.anchor.version) {
                Button("Show current installation") { NSWorkspace.shared.activateFileViewerSelecting([result.app.path]) }
            } else if let page = GitSource.page(repository: snapshot.repository, release: matches.first) {
                Link("Open", destination: page)
            }
        } else {
            Button("Refresh") { Task { await store.refresh(result.app) } }
        }
    }

    @ViewBuilder private func releaseAction(_ release: GitSource.Release) -> some View {
        if store.busy.contains(path) {
            ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub source")
        } else if let record = store.record(path), let page = GitSource.page(repository: record.repository, release: release) {
            let action = store.action(for: release, path: path, record: record)
            switch action {
            case .blocked:
                Text("Blocked").foregroundStyle(.red).help(store.messages[path] ?? "")
            case .page(let reason):
                Link("Open", destination: page).help(reason)
            case .verify, .reveal:
                Menu("Update") {
                    if case .reveal(let checked) = action {
                        Button("Show verified app in Finder") { perform(checked.asset, release: release, reveal: true) }
                    } else if case .verify(let available) = action {
                        ForEach(available) { asset in
                            Button("Download & Verify \(asset.name)") { perform(asset, release: release, reveal: false) }
                        }
                    }
                    Link("Open release page", destination: page)
                    Button("Show current installation") { NSWorkspace.shared.activateFileViewerSelecting([result.app.path]) }
                }
                .fixedSize().help("Manual update options for \(release.tag_name)")
                .accessibilityLabel("Manual update options for \(release.tag_name)")
            }
        }
    }

    private func perform(_ asset: GitSource.Asset, release: GitSource.Release, reveal: Bool) {
        Task {
            await store.check(result, release: release, asset: asset, reveal: reveal) {
                guard let row = model.results.first(where: { $0.app.path == result.app.path }) else { return false }
                return model.acceptsPersonalSource(row)
            }
        }
    }
}

private struct PersonalSourceEditor: View {
    let model: AppListModel
    @State private var anonymousLimited = false
    let result: UpdateResult
    @Environment(\.dismiss) private var dismiss
    @State private var repository: String
    @State private var track: GitSource.Track
    @State private var filenameContains: String
    @State private var includeStable: Bool
    @State private var preview: GitSource.Snapshot?
    @State private var anchor: PersonalSourceZIP.Identity?
    @State private var message: String?
    @State private var validating = false
    private let store = PersonalSources.shared

    init(result: UpdateResult, model: AppListModel) {
        self.model = model
        self.result = result
        let record = PersonalSources.shared.record(result.app.path.path)
        _repository = State(initialValue: record?.repository.full_name ?? "")
        _track = State(initialValue: record?.track ?? .stable)
        _filenameContains = State(initialValue: record?.filenameContains ?? "")
        _includeStable = State(initialValue: record?.includeStable ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.records[result.app.path.path] == nil ? "Add GitHub Source" : "Edit GitHub Source").font(.title2.bold())
            HStack {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path)).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text(verbatim: result.app.name + " · " + (result.app.shortVersion ?? ""))
                    Text(verbatim: result.app.path.path).textSelection(.enabled).foregroundStyle(.secondary)
                    Text(verbatim: result.app.bundleID ?? "").foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading) {
                Text("GitHub repository")
                HStack {
                    TextField("owner/repo or https://github.com/owner/repo", text: $repository)
                        .onChange(of: repository) { preview = nil; anchor = nil; message = nil; anonymousLimited = false }
                    Button("Validate") { validate() }.disabled(validating || repository.isEmpty)
                }
                if validating {
                    ProgressView("Checking public GitHub releases…").controlSize(.small)
                }
                if let message {
                    Label {
                        Text(verbatim: message)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
            if anonymousLimited { SourceGitHubSettingsButton(model: model) }
            Picker("Release channel", selection: $track) { ForEach(GitSource.Track.allCases, id: \.self) { Text($0.title).tag($0) } }
            LabeledContent("Filename contains") {
                TextField("Optional, e.g. Lite", text: $filenameContains)
            }
            Toggle("Include the stable release for the same version", isOn: $includeStable).disabled(track == .stable)
            if let preview {
                let releases = preview.matches(track: track, installed: anchor?.version, includeStable: includeStable)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: preview.repository.full_name).bold()
                    if let release = releases.first {
                        Text(verbatim: release.tag_name)
                        if let issue = release.tagIssue {
                            Label(issue.explanation, systemImage: "info.circle")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        let names = release.assets.filter { $0.matchesMac && $0.matches(filename: filenameContains) }.map(\.name)
                        Text(verbatim: names.isEmpty ? String(localized: "No compatible package identified by filename.") : names.joined(separator: "\n"))
                            .lineLimit(4).help(names.joined(separator: "\n"))
                    } else { Text(preview.truncated ? "No match in the latest 60 releases." : "No matching releases.") }
                }.font(.callout)
            }
            Text("Installation is manual. DuoUpdater can check a package before you reveal it in Finder.").font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                if store.record(result.app.path.path) != nil {
                    Button("Remove Source", role: .destructive) { store.remove(result.app.path.path); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(preview == nil || anchor == nil || validating)
            }
        }
        .padding(20).frame(width: 490)
    }

    private func validate() {
        let input = repository
        anonymousLimited = false
        validating = true
        preview = nil
        anchor = nil
        message = nil
        Task {
            defer { validating = false }
            do {
                guard GitSource.slug(input) != nil else {
                    throw GitSource.Failure(String(localized: "Use a public GitHub repository. Enter owner/repo or its https://github.com URL."))
                }
                let current = try await offCooperativePool { try PersonalSourceZIP.Identity(at: result.app.path) }
                let snapshot = try await PersonalGitHubClient.shared.fetch(input)
                guard repository == input else { return }
                anchor = current
                preview = snapshot
                if let previous = store.record(result.app.path.path),
                   previous.repository.id != snapshot.repository.id || previous.repository.owner.id != snapshot.repository.owner.id || previous.anchor != current {
                    message = String(localized: "Identity changed. Saving will bind this installation to the repository shown below.")
                }
            } catch {
                if repository == input {
                    message = error.localizedDescription
                    anonymousLimited = (error as? GitSource.Failure)?.disposition == .anonymousLimit
                }
            }
        }
    }

    private func save() {
        guard let preview, let anchor else { return }
        let path = result.app.path.path
        do {
            guard try PersonalSourceZIP.Identity(at: result.app.path) == anchor else { throw GitSource.Failure("Installation changed. Validate again.") }
            try store.save(.init(repository: preview.repository, track: track, filenameContains: filenameContains, includeStable: track != .stable && includeStable, anchor: anchor, lastSuccessfulCheck: preview.checked), path: path)
            store.clear(path)
            store.snapshots[path] = preview
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

extension AppListModel {
    private static let registeredPersonalSourceConflicts = Set(
        GitHubReleaseRegistry.rules.map { $0.bundleID.lowercased() } +
        VendorProbeRegistry.recipes.map { $0.bundleID.lowercased() }
    )

    func acceptsPersonalSource(_ result: UpdateResult) -> Bool {
        guard !isChecking, !isScanning, result.app.electronUpdate == nil,
              !result.homebrewSelfUpdating,
              !Self.registeredPersonalSourceConflicts.contains(result.app.recipeBundleID?.lowercased() ?? ""),
              case .noSourceCovers(.none) = rowState(for: result) else { return false }
        return result.remote == nil && result.homebrewSourceIdentifier == nil && !result.app.isMASApp
            && OneClickGateRegistry.withholding(result.app, offering: result.remote) == nil
            && !result.app.isTestFlightApp && !result.app.isToolboxManaged && !result.app.isiOSAppOnMac
    }
}
