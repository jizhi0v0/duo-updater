import SwiftUI
import AppKit
import DuoUpdaterCore

/// Caches app icons by path. `NSWorkspace.icon(forFile:)` hits the disk, and rows
/// re-render on every install-progress tick — without a cache that's one icon
/// lookup per row per tick, a real source of stutter while downloads run.
@MainActor
enum AppIconCache {
    // NSCache (vs a plain dict): it evicts under memory pressure on its own, so a
    // large library's worth of cached icons can't grow unbounded.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        // Cache miss = a synchronous disk hit on the main actor. Time it: if app
        // switches stutter, a slow icon read here is one suspect.
        let start = Date()
        let image = NSWorkspace.shared.icon(forFile: path)
        let ms = Date().timeIntervalSince(start) * 1000
        if ms > 2 {
            Log.app.info("perf icon miss: \(ms, format: .fixed(precision: 1), privacy: .public)ms for \((path as NSString).lastPathComponent, privacy: .public)")
        }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// Drop the cached icon for a path so the next lookup re-reads from disk.
    /// Called after an in-place install: the bundle is replaced but its path is
    /// unchanged, so the stale icon would otherwise persist until app restart.
    static func invalidate(_ path: String) { cache.removeObject(forKey: path as NSString) }
}

struct MenuContentView: View {
    @Bindable var model: AppListModel
    @State private var showAll = false
    @Environment(\.openWindow) private var openWindow

    private var visible: [UpdateResult] {
        showAll ? model.results
            : model.results.filter {
                model.isActionableUpdate($0) || model.needsRestart.contains($0.id)
                    || model.actionableStaged($0) != nil
                    // Hold a just-completed row for its brief "Updated ✓" beat, even
                    // though it's no longer an actionable update, before it drops out.
                    || model.justUpdated.contains($0.id)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.needsAccessibilitySetup {
                setupBanner
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 360)
        .task {
            model.refreshPermissionStatus()
            // One-time wiring: arm the background-check loop and teach the
            // notification's "View" action how to open the window.
            model.start(showUpdates: {
                openWindow(id: WorkbenchWindowView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            })
            // First open: full (networked) check. Every later open: a cheap
            // local rescan to catch background self-updates and surface Restart.
            if model.results.isEmpty {
                Log.app.info("menu .task: results empty → full refresh()")
                await model.refresh()
            } else {
                Log.app.info("menu .task: results present → refreshLocal()")
                await model.refreshLocal()
            }
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
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, result in
                        // Divider *between* rows only — a trailing one after the
                        // last row left a dangling line floating over the empty
                        // space below a short list.
                        if index > 0 { Divider() }
                        AppRow(result: result, model: model)
                    }
                }
            }
            // Size to the rows, capped at 380. A fixed 380 left a big empty void
            // under a single update (the common case) — the popover now hugs its
            // content for short lists and only starts scrolling once it would
            // exceed the cap. ~54pt per row is the measured row height.
            .frame(height: min(380, max(54, CGFloat(visible.count) * 54)))
        }
    }

    /// Shown when the incremental App Store route is selected but Accessibility isn't
    /// granted and an App Store update is actually waiting on it — a contextual nudge
    /// for users who skipped onboarding, routing back to the setup window.
    private var setupBanner: some View {
        Button {
            openWindow(id: WelcomeView.windowID)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility needed").font(.caption).fontWeight(.medium)
                    Text("App Store updates need it — finish setup")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.orange.opacity(0.08))
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duo Updater").font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.canUpdateAll && !model.isChecking && !model.isScanning {
                Button("Update All") { Task { await model.installAll() } }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .help("Install every pending update that can be applied automatically")
            }
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
            Button {
                openWindow(id: SettingsView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(12)
    }

    private var statusLine: String {
        if model.isChecking { return "Checking \(model.results.count) apps…" }
        let updates = model.updateCount
        let base = updates == 0
            ? "\(model.results.count) apps · up to date"
            : "\(updates) update\(updates == 1 ? "" : "s") available"
        if let last = model.lastCheck {
            return base + " · checked \(Self.checkedAgo(last))"
        }
        return base
    }

    /// "checked just now" / "checked 2m ago". Guards the just-finished case: the
    /// relative formatter rounds a sub-second (or microscopically future, from
    /// clock jitter) interval to "in 0 seconds", which read as a wrong-tense
    /// "checked in 0s" right after a refresh. Anything within a few seconds is
    /// "just now"; older falls back to the relative formatter.
    private static func checkedAgo(_ date: Date) -> String {
        if date.timeIntervalSinceNow > -5 { return "just now" }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var footer: some View {
        HStack {
            Toggle("Show all", isOn: $showAll)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            Button("Open Window") {
                openWindow(id: WorkbenchWindowView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Release notes, traffic, and settings")
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
    @State private var showMacCompatHint = false

    private var stage: InstallStage? { model.installing[result.id] }
    private var installError: String? { model.installErrors[result.id] }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(result.app.name).font(.body)
                        if model.isRunning(result) { RunningIndicator(size: 6) }
                        ChannelTag(channel: result.app.releaseChannel)
                    }
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
            } else if let note = model.installNotes[result.id] {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu { rowMenu }
    }

    /// Right-click actions: skip the offered version, ignore the app, and (when a
    /// backup exists) roll back to the previous version.
    @ViewBuilder
    private var rowMenu: some View {
        if result.hasUpdate {
            let offered = result.remote?.displayVersion ?? "this version"
            if model.prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) {
                Button("Don’t skip \(offered)") { model.prefs.clearSkip(result.app) }
            } else {
                Button("Skip \(offered)") { model.skipThisVersion(result) }
            }
        }
        Button(model.prefs.isIgnored(result.app)
            ? "Stop ignoring \(result.app.name)"
            : "Ignore \(result.app.name)") {
            model.toggleIgnore(result)
        }
        if let version = model.backupVersion(result.id) {
            Divider()
            Button("Roll back to \(version)") { Task { await model.rollback(result) } }
        }
    }

    @ViewBuilder
    private var versionLine: some View {
        if let staged = model.actionableStaged(result) {
            // Relaunch applies this staged build, which `actionableStaged` guarantees
            // is the latest — so the line is a plain installed → staged. (A staged
            // build that trails the latest isn't shown as Relaunch; it goes through
            // the normal updateAvailable line/Update button below.)
            stagedVersionLine(staged)
        } else if let older = model.downgradeNote(result) {
            // Vendor's latest is *older* than what's installed — show it muted with a
            // down-arrow (only reachable under "Show all", since the row is upToDate).
            downgradeVersionLine(older)
        } else {
            switch result.status {
            case .updateAvailable(let latest):
            HStack(spacing: 4) {
                fromVersion(latest: latest)
                Image(systemName: "arrow.right").font(.caption2)
                toVersion(latest: latest)
                // When an earlier update was installed but never restarted, the
                // "from" above is the *staged* on-disk version — the live process
                // is still older. Surface what's actually running so the row isn't
                // misread as "you're on the staged build".
                if let running = model.runningVersion(result.id) {
                    Text("· current \(running)")
                        .foregroundStyle(.tertiary)
                        .help("Still running \(running) — restart pending from an earlier update")
                }
            }
            .font(.caption)
            // Long date-style versions (Warp) would otherwise wrap mid-number;
            // keep it one line and shrink slightly instead.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            default:
                Text("v\(result.app.shortVersion ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// installed ↓ older — the vendor's latest trails what's installed. Muted (no
    /// alarm) and action-less: you're ahead, nothing to do. The tooltip names the
    /// benign reasons so it doesn't read as "something's wrong".
    @ViewBuilder
    private func downgradeVersionLine(_ older: String) -> some View {
        let installed = result.app.shortVersion ?? "?"
        HStack(spacing: 4) {
            Text(installed)
            Image(systemName: "arrow.down").font(.caption2)
            Text(older)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .help("The vendor's latest is \(older) — older than your \(installed). You're ahead, so there's nothing to do. Usually a beta channel, a pulled release, or a lagging check.")
    }

    /// The staged-relaunch version line: installed → staged. `actionableStaged`
    /// guarantees the staged build is the latest, so there's nothing newer to note.
    @ViewBuilder
    private func stagedVersionLine(_ staged: StagedSelfUpdate) -> some View {
        HStack(spacing: 4) {
            Text(result.app.shortVersion ?? "?")
            Image(systemName: "arrow.right").font(.caption2)
            Text(staged.version).fontWeight(.semibold).foregroundStyle(.tint)
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// True when this update keeps the same marketing version but bumps the
    /// build — e.g. Surge shipping "6.6.0 (11270)" over "6.6.0 (11260)". The
    /// comparator catches it on the build key, but the marketing version alone
    /// reads as "6.6.0 → 6.6.0", so we surface the build numbers instead.
    private func buildBump(latest: String) -> (installed: String, remote: String)? {
        guard latest == result.app.shortVersion,
              let installedBuild = result.app.buildVersion,
              let remoteBuild = result.remote?.version,
              installedBuild != remoteBuild else { return nil }
        return (installedBuild, remoteBuild)
    }

    /// The installed-version side of the "from → to" line.
    @ViewBuilder
    private func fromVersion(latest: String) -> some View {
        let marketing = result.app.shortVersion ?? "?"
        if let bump = buildBump(latest: latest) {
            // Marketing version is just context; the build is what changed.
            Text(marketing).foregroundStyle(.secondary)
            + Text(" (\(bump.installed))")
        } else {
            Text(marketing)
        }
    }

    /// The available-version side. When only the build changed, highlight the
    /// build number — not the unchanged marketing version — so the eye lands on
    /// what's actually new.
    @ViewBuilder
    private func toVersion(latest: String) -> some View {
        if let bump = buildBump(latest: latest) {
            Text("\(latest) ").foregroundStyle(.secondary)
            + Text("(\(bump.remote))").fontWeight(.semibold).foregroundStyle(.tint)
        } else {
            Text(latest).fontWeight(.semibold).foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let appName = model.awaitingQuitConfirm[result.id] {
            // An incremental App Store update finished downloading but the app is
            // running, so App Store is asking to quit it. We paused rather than
            // quitting the user's app mid-work — tapping this presses Continue (and
            // we reopen the app once the new build lands).
            quitToFinishButton(appName)
        } else if model.relaunching.contains(result.id) {
            // Mid-relaunch: the app is quit and we're waiting for the swap to land —
            // either its own ShipIt (staged self-update) or storedownloadd after we
            // pressed App Store's Continue. A spinner here both signals progress and
            // (because it replaces the button) prevents a second click firing again.
            relaunchingIndicator
        } else if model.justUpdated.contains(result.id) {
            // Just landed and fully in effect — a brief confirmation so the row reads
            // as "done", not as a progress bar that vanished. It clears itself after a
            // couple of seconds, then the up-to-date row filters out.
            updatedIndicator
        } else if let stage {
            installProgress(stage)
        } else if model.prefs.isIgnored(result.app) {
            // Surfaced only under "Show all" — a muted tag with manage actions in
            // the context menu, so an ignored app never offers an Update button.
            ignoredTag
        } else if result.hasUpdate
            && model.prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) {
            skippedTag
        } else if let staged = model.actionableStaged(result) {
            // The app's own updater already downloaded *the latest* and is waiting to
            // swap it in on the next quit ("Relaunch to update"). Offer the relaunch
            // — never our own Update — so we don't re-download the same bytes or
            // collide with the pending swap. Only when the staged build IS the latest:
            // a staged build that trails a newer release falls through to Update (a
            // direct jump), since relaunching to it wouldn't get you current.
            relaunchToUpdateButton(staged)
        } else if model.needsRestart.contains(result.id) && !result.hasUpdate {
            // Restart is derived from disk-vs-running version, not the remote
            // check — so surface it directly off `needsRestart` rather than from
            // inside the status switch. That keeps the button steady across a
            // refresh's transient `.unknown`/`.checking` statuses, instead of
            // briefly flashing the source hint ("—") until the check finishes.
            restartButton
        } else {
            switch result.status {
            case .updateAvailable:
                if result.remote?.sourceName == "Toolbox" {
                    // Detected via Toolbox's own cache — it installs, we just route.
                    toolboxButton
                } else if result.remote?.sourceName == "TestFlight" {
                    // Detected via TestFlight's cache — it installs, we just route.
                    testFlightButton
                } else if model.vendorDefersToSelfUpdater(result) {
                    // Running self-updating vendor app + "defer while running" policy:
                    // open its own update path instead of swapping under it.
                    openSelfUpdaterButton
                } else if result.isMajorUpgrade && (model.canAutoInstall(result) || model.requiresInstaller(result)) {
                    majorUpgradeBadge
                } else if model.canAutoInstall(result) {
                    autoUpdateButton
                } else if model.requiresInstaller(result) {
                    installerButton
                } else if let info = result.remote?.appStore {
                    appStoreTrailing(info)
                } else {
                    openButton
                }
            case .error:
                errorBadge
            case .unknown:
                Text(sourceHint).font(.caption2).foregroundStyle(.tertiary)
            case .appStoreManaged:
                appStoreManagedLabel
            case .toolboxManaged:
                toolboxButton
            case .testFlightManaged:
                testFlightManagedLabel
            case .upToDate:
                // needsRestart is handled above, before the status switch.
                if result.app.isMASApp {
                    // We checked it against the store and it's current — but keep
                    // the "App Store" signal so a managed app never looks like an
                    // app we can update ourselves (a bare ✅ reads the same as
                    // Sparkle/brew). Same label as `.appStoreManaged`.
                    appStoreManagedLabel
                } else if result.app.isTestFlightApp {
                    // Current on TestFlight — keep the channel tag rather than a
                    // bare check, so it never reads like a self-updatable app.
                    testFlightManagedLabel
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
                // Fixed-width, right-aligned, monospaced digits: "2%" and "100%"
                // both end at the same edge, so neither the bar nor the row moves.
                Text("\(Int(f * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            } else {
                ProgressView().controlSize(.small)
                Text(stageLabel(stage))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        // Right-align the bar+label as a tight group inside a constant-width slot,
        // so it sits flush right (matching the buttons) and the row never reflows
        // as the percentage changes — the source of the jitter with many downloads.
        .frame(width: 96, alignment: .trailing)
    }

    private func stageLabel(_ stage: InstallStage) -> String {
        switch stage {
        case .checking: return "Checking"
        case .downloading(let f): return "\(Int(f * 100))%"
        case .verifyingSignature, .verifyingCodeSignature: return "Verifying"
        case .extracting: return "Extracting"
        case .installing: return "Installing"
        case .runningCommand: return "Installing"
        case .done: return "Done"
        }
    }

    private var autoUpdateButton: some View {
        Button("Update") { Task { await model.install(result) } }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
    }

    /// Muted tag for an app the user has chosen to ignore — right-click to manage.
    private var ignoredTag: some View {
        Text("Ignored").font(.caption2).foregroundStyle(.tertiary)
            .help("Hidden from update checks — right-click to stop ignoring")
    }

    /// Muted tag for an update whose offered version the user skipped.
    private var skippedTag: some View {
        Text("Skipped").font(.caption2).foregroundStyle(.tertiary)
            .help("You skipped this version — right-click to un-skip")
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

    /// The app self-downloaded a newer build (Squirrel/ShipIt staged it); a
    /// relaunch swaps it in. Unlike `restartButton` this routes to
    /// `relaunchStagedUpdate`, which quits the app and lets *its own* ShipIt do the
    /// swap+relaunch (reopening it ourselves makes ShipIt abort). No extra download
    /// — the bytes are already staged on disk.
    private func relaunchToUpdateButton(_ staged: StagedSelfUpdate) -> some View {
        Button("Relaunch") { Task { await model.relaunchStagedUpdate(result) } }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(result.app.name) already downloaded \(staged.version) — relaunch to apply it (no extra download)")
    }

    /// An incremental App Store update is downloaded but the app is running, so the
    /// store wants to quit it to install. Tapping presses the store's Continue (via
    /// the AX installer's awaited `confirmQuit`); the app quits, the update lands,
    /// and we reopen it. Labelled "Relaunch" to match the other quit-to-apply action.
    private func quitToFinishButton(_ appName: String) -> some View {
        Button("Relaunch") { model.confirmQuit(result.id, proceed: true) }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(appName.isEmpty ? result.app.name : appName) must quit to finish updating — click to quit it, install, and reopen")
    }

    /// Shown while a staged relaunch is in flight: the app is quit and its own
    /// ShipIt is swapping the bundle. Matches the install spinner's footprint.
    private var relaunchingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Relaunching…")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 96, alignment: .trailing)
        .help("Quit \(result.app.name) — waiting for it to swap in the new version and reopen")
    }

    private var updatedIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Updated")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 96, alignment: .trailing)
        .help("\(result.app.name) updated to \(result.app.shortVersion ?? "the latest version")")
    }

    private var restartHelp: String {
        let disk = result.app.shortVersion ?? "the new version"
        if let running = model.runningVersion(result.id) {
            return "Running \(running) but \(disk) is installed — restart to apply it"
        }
        return "You’re running an older version — restart to finish updating"
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

    /// Fallback for updates we can detect but not install in place (GitHub
    /// releases, self-updating apps like Chrome). Opens the official download /
    /// releases page in the browser so the user can grab it through the app's own
    /// channel; only reveals in Finder if there's no URL to open.
    private var openButton: some View {
        Button("Open") { openAction() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help(openHelp)
    }

    /// Shown for a running self-updating vendor app under the "defer while running"
    /// policy: open the app's own update path rather than installing over it.
    private var openSelfUpdaterButton: some View {
        Button("Open") { model.openSelfUpdater(result) }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("\(result.app.name) is running — open it and let its own updater apply \(result.remote?.displayVersion ?? "the update"). Quit it, or pick “Always replace” in Settings, to install directly.")
    }

    private func openAction() {
        guard let url = result.remote?.downloadURL else {
            NSWorkspace.shared.activateFileViewerSelecting([result.app.path])
            return
        }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            // App-internal deep link (e.g. chrome://settings/help). Hand it to the
            // app itself so it acts through its own update channel — for Chrome,
            // opening that page triggers a Keystone update check + download.
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: result.app.path, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// JetBrains Toolbox manages this app's updates. Toolbox registers no URL
    /// scheme, so there's no per-tool deep link — we just open the Toolbox window,
    /// where the user updates it through its own channel.
    private var toolboxButton: some View {
        Button("Toolbox") { openToolbox() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")
    }

    private func openToolbox() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.jetbrains.toolbox") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// TestFlight manages this beta's updates. There's no per-app deep link we can
    /// rely on, so we just open TestFlight, where the user installs the update
    /// through its own channel.
    private var testFlightButton: some View {
        Button("TestFlight") { openTestFlight() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by TestFlight — open TestFlight to update \(result.app.name)")
    }

    private func openTestFlight() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.TestFlight") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private var openHelp: String {
        guard let url = result.remote?.downloadURL else { return "Reveal in Finder" }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            return "Open \(result.app.name)’s built-in updater (it updates itself)"
        }
        return "Open the official download page"
    }

    /// App Store apps: when the app is in the signed-in region, a Get button
    /// deep-links to the product page; when it isn't, a globe badge opens a
    /// popover explaining the region lock (the store would just say "App Not
    /// Available").
    @ViewBuilder
    private func appStoreTrailing(_ info: AppStoreAvailability) -> some View {
        if info.isLatestMacIncompatible {
            // A newer build exists but Apple has marked it as no longer running on
            // Macs — installing it here is impossible, so flag it rather than
            // offering a "Get" the store would reject.
            Button { showMacCompatHint = true } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("The latest version no longer supports this Mac — click for details")
            .popover(isPresented: $showMacCompatHint, arrowEdge: .bottom) {
                macCompatHintPopover(info)
            }
        } else if info.isRegionMismatch {
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
            // The region lock blocks a *fresh install* (the product page is "App Not
            // Available" under a \(here) account), but it does NOT block updating an
            // app you already have: an installed region-locked app still shows up in
            // App Store's own Updates list, and DuoUpdater can drive that update
            // entirely in the background. The catch is timing — the store surfaces
            // these into its Updates list on its own schedule.
            Text("You already have it installed, so it can still be updated — DuoUpdater drives the App Store’s Updates list in the background (a fresh install would need a \(there) account). It only works once the App Store has listed this update; if it hasn’t yet, try again later.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Update in background") {
                    showRegionHint = false
                    Task { await model.install(result) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Open App Store") { openInAppStore(info) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func macCompatHintPopover(_ info: AppStoreAvailability) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not supported on this Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("\(result.app.name) is an iPhone/iPad app running on Apple Silicon. Its latest version\(result.remote?.displayVersion.map { " (\($0))" } ?? "") no longer supports Mac, so the App Store won't install it on this device.")
                .font(.callout)
            Text("You can keep using the installed version (\(result.app.shortVersion ?? "current")). Updating isn't possible until the developer ships a Mac-compatible build again — it's the vendor's choice, not a refresh problem.")
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

    /// The "App Store" tag shown for any store-managed app — whether it's up to
    /// date or the lookup returned nothing. Either way, updates are the store's
    /// job, so the row never offers an action we can't perform.
    private var appStoreManagedLabel: some View {
        Text("App Store").font(.caption2).foregroundStyle(.tertiary)
            .help("Managed by the App Store — it handles this app's updates")
    }

    /// The "TestFlight" tag shown for a TestFlight-managed app that's current (or
    /// whose cache returned nothing). Updates are TestFlight's job, so the row
    /// shows the channel rather than an action we can't perform here.
    private var testFlightManagedLabel: some View {
        Text("TestFlight").font(.caption2).foregroundStyle(.tertiary)
            .help("Managed by TestFlight — it handles this beta's updates")
    }

    /// A source was tried and failed — most often a transient GitHub rate-limit.
    /// Unlike `.unknown`'s dead "—", this state is retryable, so it's a button:
    /// one click re-checks just this app. The tooltip carries the failure reason.
    private var errorBadge: some View {
        Button { Task { await model.retry(result) } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(.orange)
        .help(errorText.isEmpty
            ? "Update check failed — click to retry"
            : "\(errorText) — click to retry")
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
