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
    let retryQuery: @MainActor () -> Void
    @Environment(\.openWindow) private var openWindow
    // When the sheet is clicked from another window (or via accessibility),
    // NSApp.keyWindow can still refer to Settings. Use the button's own window.
    private struct WindowAnchor: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    @State private var anchor = NSView()
    @State private var request = UUID()

    var body: some View {
        Button("Open Settings") {
            request = UUID()
            model.personalSourceSettingsRequest = .init(id: request, origin: anchor.window, retryQuery: retryQuery)
            model.requestedSettingsSection = .github
            model.requestedSettingsAnchor = .githubCLI
            openWindow(id: SettingsView.windowID)
            model.surfaceWindow(sceneID: SettingsView.windowID)
        }
        .background(WindowAnchor(view: anchor).frame(width: 0, height: 0))
        .onDisappear {
            if model.personalSourceSettingsRequest?.id == request {
                model.personalSourceSettingsRequest = nil
            }
        }
    }
}

struct PersonalSourceControls: View {
    let result: UpdateResult
    let model: AppListModel
    let isEligible: Bool
    let isRoundInFlight: Bool
    @State private var editor = false
    private let store = PersonalSources.shared
    private var path: String { result.app.path.path }

    var body: some View {
        Group {
            if let record = store.record(path) {
                Menu {
                    Button("Edit Source…") { editor = true }
                        .disabled(record.replacementID != nil)
                    if record.grant != nil {
                        Button("Revoke One-Click Updates") {
                            do { try store.setReplacement(false, path: path) }
                            catch { store.messages[path] = error.localizedDescription }
                        }
                    }
                    if store.recovering.contains(path) {
                        Button("Show Recovery Files") {
                            NSWorkspace.shared.activateFileViewerSelecting([PersonalSourceReplacement.directory(for: result.app.path)])
                        }
                    }
                    Button("Check Again") { Task { await store.refresh(result.app) } }
                        .disabled(isRoundInFlight || store.busy.contains(path) || record.replacementID != nil)
                    Divider()
                    if let page = GitSource.page(repository: record.repository, release: nil) {
                        Link("Open release page", destination: page)
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.app.path])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text(verbatim: "GitHub Releases"))
                .help(record.repository.full_name)
            } else if store.records[path] == nil && isEligible {
                Button("Add GitHub Source…", systemImage: "plus") { editor = true }
                    .disabled(isRoundInFlight)
            }
        }
        .controlSize(.small)
        .sheet(isPresented: $editor) { PersonalSourceEditor(result: result, model: model) }
        .task(id: path) { if store.snapshot(for: path) == nil { await store.refresh(result.app) } }
    }
}

struct PersonalSourceNotice: View {
    let result: UpdateResult
    let model: AppListModel
    let isCurrent: Bool
    @State private var confirmReplacement = false
    @State private var proposedBinding: PersonalSources.BindingRecord?
    private let store = PersonalSources.shared
    private var path: String { result.app.path.path }

    var body: some View {
        if store.records[path] != nil && store.record(path) == nil {
            Text("Unsupported source configuration. Subscription paused.")
                .font(.caption).foregroundStyle(.secondary)
        } else if let message = store.messages[path], !isCurrent {
            Text(verbatim: message)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let record = store.record(path), record.grant == nil, model.acceptsPersonalSource(result),
           let release = store.candidate(result), case .reveal(let package) = store.action(for: release, path: path, record: record),
           package.permitsReplacement(using: record), !store.busy.contains(path) {
            Button("Enable One-Click Updates…") {
                proposedBinding = record
                confirmReplacement = true
            }
            .font(.callout).buttonStyle(.link)
            .alert("Allow one-click updates for this copy?", isPresented: $confirmReplacement) {
                Button("Cancel", role: .cancel) {}
                Button("I Checked the Instructions") {
                    do { try store.setReplacement(true, path: path, expected: proposedBinding) }
                    catch { store.messages[path] = error.localizedDescription }
                }
            } message: {
                if let record = proposedBinding {
                    Text("Confirm that the publisher instructs you to replace this app directly. Each update requires your click.\n\n\(record.repository.full_name) · \(record.track.rawValue)\n\(path)")
                }
            }
        }
        if let issue = store.checked[path]?.replacementIssue, !isCurrent {
            Text("Manual update only: \(issue)").font(.caption).foregroundStyle(.secondary)
        }
        if store.needsGitHubSettings.contains(path) {
            SourceGitHubSettingsButton(model: model) { Task { await store.refresh(result.app) } }
                .font(.caption).buttonStyle(.link)
        }
    }
}

struct PersonalSourceAction: View {
    let result: UpdateResult
    let model: AppListModel
    var compact = false
    var releaseState: PersonalSources.ReleaseState?
    private let store = PersonalSources.shared
    private var path: String { result.app.path.path }
    var body: some View {
        let state = releaseState ?? store.releaseState(for: result)
        if case .update(let release) = state {
            releaseAction(release)
        } else if store.busy.contains(path) {
            ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub source")
        } else if compact && store.record(path)?.handoff != nil {
            currentInstallationButton
        } else if compact {
            if state == .current {
                PopoverRowAction(state: .upToDate(channel: .none), result: result)
            } else if let record = store.record(path), let snapshot = store.snapshot(for: path), !store.paused.contains(path) {
                let matches = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable)
                if let page = GitSource.page(repository: snapshot.repository, release: matches.first) {
                    Link("Open", destination: page)
                }
            } else {
                Button("Refresh") { Task { await store.refresh(result.app) } }
            }
        }
    }

    private var currentInstallationButton: some View {
        Button("Show current installation", systemImage: "folder", action: revealCurrentInstallation)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(store.messages[path] ?? String(localized: "Show current installation"))
    }

    private func revealCurrentInstallation() {
        NSWorkspace.shared.activateFileViewerSelecting([result.app.path])
    }

    @ViewBuilder private func releaseAction(_ release: GitSource.Release) -> some View {
        if store.replacing(path) {
            if store.record(path)?.replacementID != nil {
                ProgressView().controlSize(.small).accessibilityLabel("Installing update")
            } else { Button("Cancel Update") { store.cancelReplacement(path) } }
        } else if store.busy.contains(path) {
            ProgressView().controlSize(.small).accessibilityLabel("Checking GitHub source")
        } else if let record = store.record(path), let page = GitSource.page(repository: record.repository, release: release) {
            let action = store.action(for: release, path: path, record: record)
            switch action {
            case .blocked:
                Text("Blocked").foregroundStyle(.red).help(store.messages[path] ?? "")
            case .page(let reason):
                Link("Open", destination: page).help(reason)
            case .verify, .reveal:
                if case .reveal(let package) = action, record.grant?.path == path, package.permitsReplacement(using: record) {
                    Button("Update \(package.identity.version)") {
                        store.startReplacement(result, package: package, installed: { await model.appsLane.handle(.diskChanged) }) {
                            model.results.first(where: { $0.app.path == result.app.path }).map(model.acceptsPersonalSource) == true
                        }
                    }.buttonStyle(.borderedProminent)
                }
                Menu {
                    if case .reveal(let checked) = action {
                        Button("Show verified app in Finder") { perform(checked.asset, release: release, reveal: true) }
                    } else if case .verify(let available) = action {
                        ForEach(available) { asset in
                            Button("Download & Verify \(asset.name)") { perform(asset, release: release, reveal: false) }
                        }
                    }
                    Link("Open release page", destination: page)
                    Button("Show current installation", action: revealCurrentInstallation)
                } label: {
                    if case .reveal(let package) = action, record.grant != nil, package.permitsReplacement(using: record) {
                        if compact { Image(systemName: "folder") } else { Text("Manual Updates") }
                    } else { Text("Update") }
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

struct PersonalSourceRecoveryNotice: View {
    let path: String
    @State private var confirming = false
    private let store = PersonalSources.shared
    private var target: URL { URL(fileURLWithPath: path) }

    var body: some View {
        HStack {
            Label("Update recovery needs attention", systemImage: "exclamationmark.triangle")
            Text(verbatim: path).lineLimit(1).truncationMode(.middle).help(store.messages[path] ?? path)
            Spacer()
            Button("Show Recovery Files") {
                NSWorkspace.shared.activateFileViewerSelecting([PersonalSourceReplacement.directory(for: target)])
            }
            Button("Keep Current App") { confirming = true }
                .disabled(store.busy.contains(path) || store.replacing(path))
                .confirmationDialog("Keep Current App", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Keep Current App") {
                        do {
                            if let archive = try store.keepCurrentApp(target) {
                                NSWorkspace.shared.activateFileViewerSelecting([archive])
                            }
                        } catch { store.messages[path] = error.localizedDescription }
                    }
                } message: {
                    Text("Duo Updater will keep the app at this path, preserve any recovery files, and revoke its one-click authorization.")
                }
        }.padding(8).background(.bar)
    }
}

private struct PersonalSourceEditor: View {
    let model: AppListModel
    @State private var needsGitHubSettings = false
    let result: UpdateResult
    @Environment(\.dismiss) private var dismiss
    @State private var repository: String
    @State private var track: GitSource.Track
    @State private var filters: [String: String]
    private var filenameContains: String { filters[track.rawValue] ?? "" }
    @State private var includeStable: Bool
    @State private var fetchedPreview: GitSource.Snapshot?
    @State private var previewRevision = 0
    private var preview: GitSource.Snapshot? { store.accessible(fetchedPreview, since: previewRevision) }
    @State private var anchor: PersonalSourceZIP.Identity?
    @State private var message: String?
    @State private var validationTask: Task<Void, Never>?
    private var validating: Bool { validationTask != nil }
    private let store = PersonalSources.shared
    private var canSave: Bool {
        let path = result.app.path.path
        guard !validating, store.records[path] != nil || !model.listActivity.isRoundInFlight else { return false }
        return (preview != nil && anchor != nil) || store.record(path, matchingRepository: repository) != nil
    }

    init(result: UpdateResult, model: AppListModel) {
        self.model = model
        self.result = result
        let record = PersonalSources.shared.record(result.app.path.path)
        _repository = State(initialValue: record?.repository.full_name ?? "")
        _track = State(initialValue: record?.track ?? .stable)
        _filters = State(initialValue: record?.channelFilters ?? [:])
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
            ViewThatFits(in: .vertical) {
                editorFields.fixedSize(horizontal: false, vertical: true)
                ScrollView { editorFields.padding(3) }
            }
            .frame(maxHeight: 346)
            Divider()
            HStack {
                if store.record(result.app.path.path) != nil {
                    Button("Remove Source", role: .destructive) { store.remove(result.app.path.path); dismiss() }
                }
                Spacer()
                Button(validating ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(validating ? nil : .cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(20).frame(width: 490)
        .onDisappear { cancelValidation() }
        .onChange(of: preview != nil) { _, isAvailable in
            if fetchedPreview != nil, !isAvailable {
                fetchedPreview = nil
                anchor = nil
                message = nil
            }
        }
    }

    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("GitHub repository").fontWeight(.semibold)
                HStack {
                    TextField("GitHub repository", text: $repository, prompt: Text(verbatim: "owner/repo"))
                        .labelsHidden()
                        .onChange(of: repository) {
                            cancelValidation()
                            fetchedPreview = nil
                            anchor = nil
                            message = nil
                            needsGitHubSettings = false
                        }
                    validationControl
                }
                Text(verbatim: "owner/repo  ·  https://github.com/owner/repo")
                    .font(.caption).foregroundStyle(.secondary)
                if let message {
                    Label {
                        Text(verbatim: message).textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }.font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if needsGitHubSettings { SourceGitHubSettingsButton(model: model, retryQuery: validate) }
            }
            Picker("Release channel", selection: $track) {
                ForEach(GitSource.Track.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if track != .stable {
                Toggle("Include the stable release for the same version", isOn: $includeStable)
            }
            LabeledContent("Filename contains") {
                TextField("Optional, e.g. Lite", text: Binding(
                    get: { filenameContains }, set: { filters[track.rawValue] = $0 }
                ))
            }
            Text("Optional. Each channel remembers its own filename filter.")
                .font(.caption).foregroundStyle(.secondary)
            if let preview { validationResult(preview) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validationControl: some View {
        ZStack {
            Button(action: validate) {
                Text("Validate").frame(minWidth: 84)
            }
            .disabled(validating || repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(validating ? 0 : 1)
            .accessibilityHidden(validating)

            // Size both states together so validation never resizes the input.
            HStack(spacing: 5) {
                Color.clear.frame(width: 12, height: 12)
                    .overlay {
                        if validating { ProgressView().controlSize(.mini) }
                    }
                    .accessibilityHidden(true)
                Text("Checking…").font(.callout).foregroundStyle(.secondary)
                Button("Cancel validation", systemImage: "xmark.circle.fill", action: cancelValidation)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Cancel validation")
                    .keyboardShortcut(validating ? .cancelAction : nil)
            }
            .fixedSize()
            .disabled(!validating)
            .opacity(validating ? 1 : 0)
            .accessibilityHidden(!validating)
        }
    }

    private func validationResult(_ snapshot: GitSource.Snapshot) -> some View {
        let release = snapshot.matches(track: track, installed: anchor?.version, includeStable: includeStable).first
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text("Repository verified").fontWeight(.semibold)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Text(verbatim: snapshot.repository.full_name).textSelection(.enabled)
            }
            Divider()
            if let release {
                LabeledContent("Release channel") {
                    Text(verbatim: track.title + " · " + release.tag_name)
                }
                if let issue = release.tagIssue {
                    Label(issue.explanation, systemImage: "info.circle").foregroundStyle(.secondary)
                }
                let names = release.assets.filter { $0.matchesMac && $0.matches(filename: filenameContains) }.map(\.name)
                LabeledContent("Matching files") {
                    VStack(alignment: .trailing, spacing: 3) {
                        if names.isEmpty { Text("No compatible package identified by filename.") }
                        ForEach(names.indices, id: \.self) { index in
                            Text(verbatim: names[index]).textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text(snapshot.truncated ? "No match in the latest 60 releases." : "No matching releases.")
            }
            Text("Package signature has not been checked.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    private func validate() {
        let input = repository
        let knownRepositoryID = preview?.repository.id ?? store.record(result.app.path.path, matchingRepository: input)?.repository.id
        needsGitHubSettings = false
        cancelValidation()
        fetchedPreview = nil
        anchor = nil
        message = nil
        let generation = GitHubCredentials.shared.generation
        let revision = store.repositoryRevision
        validationTask = Task {
            defer { if !Task.isCancelled { validationTask = nil } }
            do {
                guard GitSource.slug(input) != nil else {
                    throw GitSource.Failure(String(localized: "Enter owner/repo or its https://github.com URL."))
                }
                let current = try await offCooperativePool { try PersonalSourceZIP.Identity(at: result.app.path) }
                try Task.checkCancellation()
                let snapshot = try await PersonalGitHubClient.shared.fetch(input)
                guard !Task.isCancelled, repository == input, generation == GitHubCredentials.shared.generation, store.accessible(snapshot, since: revision) != nil else { return }
                anchor = current
                previewRevision = revision
                fetchedPreview = snapshot
                if let previous = store.record(result.app.path.path),
                   previous.repository.id != snapshot.repository.id || previous.repository.owner.id != snapshot.repository.owner.id || previous.anchor != current {
                    message = String(localized: "Identity changed. Saving will bind this installation to the repository shown below.")
                }
            } catch {
                if !Task.isCancelled, repository == input, generation == GitHubCredentials.shared.generation {
                    let failure = error as? GitSource.Failure
                    if failure?.confirmsRepositoryDenial == true {
                        store.repositoryDenied(input, id: knownRepositoryID, since: revision, message: error.localizedDescription)
                    }
                    message = error.localizedDescription
                    needsGitHubSettings = failure?.disposition.needsGitHubSettings == true
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let path = result.app.path.path
        do {
            if store.records[path] == nil {
                guard let current = model.results.first(where: { $0.app.path == result.app.path }), model.acceptsPersonalSource(current) else {
                    throw GitSource.Failure(String(localized: "This app is no longer eligible for a custom source."))
                }
            }
            let validation = preview.flatMap { snapshot in anchor.map { (snapshot: snapshot, anchor: $0, revision: previewRevision) } }
            try store.saveConfiguration(for: result.app.path, repository: repository, track: track,
                                        filters: filters, includeStable: includeStable, validation: validation)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

extension AppListModel {
    func acceptsPersonalSource(_ result: UpdateResult) -> Bool {
        guard !isChecking, !isScanning, PersonalSources.lacksBuiltInSource(result),
              case .noSourceCovers(.none) = rowState(for: result) else { return false }
        return true
    }

    /// The chosen subscription track is a display label. Keep it through
    /// refreshes and other transient row actions while the source still applies.
    func displayedReleaseChannel(for result: UpdateResult) -> ReleaseChannel {
        guard let record = PersonalSources.shared.record(result.app.path.path),
              case .unknown = result.status, PersonalSources.lacksBuiltInSource(result) else {
            return result.effectiveReleaseChannel
        }
        switch record.track {
        case .stable: return .stable
        case .preview: return .preview
        case .nightly: return .nightly
        }
    }
}
