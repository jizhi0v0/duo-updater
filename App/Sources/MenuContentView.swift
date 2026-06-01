import SwiftUI
import AppKit
import DuoUpdaterCore

struct MenuContentView: View {
    @Bindable var model: AppListModel
    @State private var showAll = false

    private var visible: [UpdateResult] {
        showAll ? model.results
            : model.results.filter { $0.hasUpdate || model.needsRestart.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360)
        .task {
            if model.results.isEmpty { await model.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.results.isEmpty {
            ContentUnavailableView(
                model.isScanning ? "Scanning…" : "No apps yet",
                systemImage: "magnifyingglass"
            )
            .frame(height: 200)
        } else if visible.isEmpty {
            ContentUnavailableView(
                "Everything is up to date",
                systemImage: "checkmark.seal.fill",
                description: Text("Toggle “Show all” to see every app.")
            )
            .frame(height: 200)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { result in
                        AppRow(result: result, model: model)
                        Divider()
                    }
                }
            }
            .frame(height: 380)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duo Updater").font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isScanning || model.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isScanning || model.isChecking)
            .help("Rescan and check for updates")
        }
        .padding(12)
    }

    private var statusLine: String {
        if model.isChecking { return "Checking \(model.results.count) apps…" }
        let updates = model.updateCount
        return updates == 0
            ? "\(model.results.count) apps · up to date"
            : "\(updates) update\(updates == 1 ? "" : "s") available"
    }

    private var footer: some View {
        HStack {
            Toggle("Show all", isOn: $showAll)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct AppRow: View {
    let result: UpdateResult
    @Bindable var model: AppListModel
    @State private var showRegionHint = false
    @State private var showMajorWarning = false

    private var stage: InstallStage? { model.installing[result.id] }
    private var installError: String? { model.installErrors[result.id] }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: result.app.path.path))
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.app.name).font(.body)
                    versionLine
                }
                Spacer()
                trailing
            }
            if let installError {
                Text(installError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var versionLine: some View {
        switch result.status {
        case .updateAvailable(let latest):
            HStack(spacing: 4) {
                Text(result.app.shortVersion ?? "?")
                Image(systemName: "arrow.right").font(.caption2)
                Text(latest).fontWeight(.semibold).foregroundStyle(.tint)
            }
            .font(.caption)
        default:
            Text("v\(result.app.shortVersion ?? "?")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let stage {
            installProgress(stage)
        } else {
            switch result.status {
            case .updateAvailable:
                if result.isMajorUpgrade && (model.canAutoInstall(result) || model.requiresInstaller(result)) {
                    majorUpgradeBadge
                } else if model.canAutoInstall(result) {
                    autoUpdateButton
                } else if model.isSelfUpdating(result) {
                    selfUpdateButton
                } else if model.requiresInstaller(result) {
                    installerButton
                } else if let info = result.remote?.appStore {
                    appStoreTrailing(info)
                } else {
                    revealButton
                }
            case .error:
                errorBadge
            case .unknown:
                Text(sourceHint).font(.caption2).foregroundStyle(.tertiary)
            case .upToDate:
                if model.needsRestart.contains(result.id) {
                    restartButton
                } else {
                    Image(systemName: "checkmark").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func installProgress(_ stage: InstallStage) -> some View {
        HStack(spacing: 6) {
            if case .downloading(let f) = stage {
                ProgressView(value: f).frame(width: 50).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(stageLabel(stage)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func stageLabel(_ stage: InstallStage) -> String {
        switch stage {
        case .checking: return "Checking"
        case .downloading(let f): return "\(Int(f * 100))%"
        case .verifyingSignature, .verifyingCodeSignature: return "Verifying"
        case .extracting: return "Extracting"
        case .installing: return "Installing"
        case .relaunching: return "Relaunching"
        case .runningCommand: return "Installing"
        case .done: return "Done"
        }
    }

    private var autoUpdateButton: some View {
        Button("Update") { Task { await model.install(result) } }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
    }

    /// On disk it's current, but the running instance is older — offer a
    /// relaunch so the update actually takes effect.
    private var restartButton: some View {
        Button("Restart") { Task { await model.restart(result) } }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help(restartHelp)
    }

    private var restartHelp: String {
        let disk = result.app.shortVersion ?? "the new version"
        if let running = model.runningVersion(result.id) {
            return "Running \(running) but \(disk) is installed — restart to apply it"
        }
        return "You’re running an older version — restart to finish updating"
    }

    /// Electron/Squirrel app that updates itself: respect its own channel
    /// (often fresher than the cask) — open the app and let it self-update.
    private var selfUpdateButton: some View {
        Button("Open") { NSWorkspace.shared.open(result.app.path) }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("This app updates itself — open it to install the update")
    }

    /// pkg cask: download the official installer and open it (system installer
    /// asks for admin). Not an in-place swap, so it's a plain bordered button.
    private var installerButton: some View {
        Button("Update") { Task { await model.install(result) } }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Downloads the official installer and opens it (asks for admin)")
    }

    /// Major version bumps may cross a paid app's license boundary. Like the
    /// region-lock case, we don't offer a one-click button — an amber badge
    /// opens a popover that explains the risk before any install.
    private var majorUpgradeBadge: some View {
        Button { showMajorWarning = true } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .buttonStyle(.borderless)
        .help("Major version upgrade — click before updating")
        .popover(isPresented: $showMajorWarning, arrowEdge: .bottom) {
            majorUpgradePopover
        }
    }

    private var majorUpgradePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Major version upgrade", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("\(result.app.name) \(result.app.shortVersion ?? "?") → \(result.remote?.displayVersion ?? "?") is a major new version. If this is a commercial app, it may need a new license — with an expired subscription the update can drop into a limited/trial mode.")
                .font(.callout)
            Text("Continue only if it’s free or your license covers the new version. Your current version is moved to the Trash, so you can restore it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Update anyway") {
                showMajorWarning = false
                Task { await model.install(result) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290)
    }

    /// Reveal-in-Finder fallback for sources we can't act on inline yet.
    private var revealButton: some View {
        Button("Get") { NSWorkspace.shared.activateFileViewerSelecting([result.app.path]) }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Reveal in Finder")
    }

    /// App Store apps: when the app is in the signed-in region, a Get button
    /// deep-links to the product page; when it isn't, a globe badge opens a
    /// popover explaining the region lock (the store would just say "App Not
    /// Available").
    @ViewBuilder
    private func appStoreTrailing(_ info: AppStoreAvailability) -> some View {
        if info.isRegionMismatch {
            Button { showRegionHint = true } label: {
                Image(systemName: "globe.badge.chevron.backward")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("Not available in your App Store region — click for details")
            .popover(isPresented: $showRegionHint, arrowEdge: .bottom) {
                regionHintPopover(info)
            }
        } else {
            Button("Get") { openInAppStore(info) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("Open in the App Store")
        }
    }

    private func openInAppStore(_ info: AppStoreAvailability) {
        if let url = info.deepLink ?? result.remote?.downloadURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func regionHintPopover(_ info: AppStoreAvailability) -> some View {
        let here = info.homeRegion.map(Self.regionName) ?? "your region"
        let there = Self.regionName(info.availableRegion)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Region-locked", systemImage: "globe.badge.chevron.backward")
                .font(.headline)
            Text("\(result.app.name) isn’t in your App Store region (\(here)). It’s listed in \(there)\(result.remote?.displayVersion.map { " — latest \($0)" } ?? "").")
                .font(.callout)
            Text("Updating it requires signing the App Store into an Apple ID for \(there). No tool can install it under a \(here) account — it’s an Apple licensing restriction, not a refresh problem.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open App Store anyway") { openInAppStore(info) }
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290)
    }

    private static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    private var errorBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help(errorText)
    }

    private var errorText: String {
        if case .error(let e) = result.status { return e }
        return ""
    }

    private var sourceHint: String {
        if result.app.isMASApp { return "App Store" }
        if result.app.sparkleFeedURL != nil { return "Sparkle" }
        return "—"
    }
}
