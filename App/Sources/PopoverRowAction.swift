import SwiftUI
import AppKit
import DuoUpdaterCore

/// The popover's row action — the trailing edge of every row in the menu bar.
///
/// Model-free by construction: it takes the shared `RowActionState`, the row, and
/// plain closures. That is what lets `RowStateGallery` draw all 30 states without
/// an `AppListModel` (whose `init` registers notification permission, arms timers
/// and starts FS watchers — not things a screenshot tool should do).
///
/// This window keeps the richer affordances on purpose: a major upgrade opens a
/// licence-boundary explanation, a region-locked App Store row explains why. The
/// workbench points at this window for those instead of repeating them.
struct PopoverRowAction: View {
    let state: RowActionState
    let result: UpdateResult
    var actions: RowActions = .init()
    /// The version of the running process, when it differs from disk. Only feeds
    /// the Relaunch button's help text.
    var runningVersion: String?
    /// Whether the privileged helper is approved — only affects help text.
    var helperEnabled: Bool = true
    /// How much of the download readout fits. Measured by the ROW, which knows the
    /// name's width, and handed down — this view draws what it is told to.
    var downloadReadout: DownloadReadout = .barAndPercent
    /// Whether a stage word fits beside the spinner, same reasoning.
    var showsStageLabel: (InstallStage) -> Bool = { _ in true }

    /// Owned here rather than by the row: the licence-boundary warning belongs to
    /// this control, and nothing outside it reads the flag.
    @State private var showMajorWarning = false
    @State private var showRegionHint = false
    @State private var showMacCompatHint = false

    @ViewBuilder
    var body: some View {
        // `ui = f(state)`. The ladder deciding WHICH of these applies is
        // `RowAction.state`, shared with the workbench — this window used to carry
        // its own copy in a different order, which is how the two drifted apart.
        // This window keeps the richer affordances (a major upgrade's licence
        // warning, an App Store row's region explanation); what it no longer keeps
        // is a private opinion about what the row *is*.
        switch state {
        case .awaitingQuitConfirm(let appName):
            // An incremental App Store update finished downloading but the app is
            // running, so App Store is asking to quit it. We paused rather than
            // quitting the user's app mid-work — tapping this presses Continue (and
            // we reopen the app once the new build lands).
            quitToFinishButton(appName)

        case .relaunching:
            relaunchingIndicator

        case .pendingBatchRestart:
            pendingBatchRestartButton

        case .justUpdated:
            // Just landed and fully in effect — a brief confirmation so the row reads
            // as "done", not as a progress bar that vanished. It clears itself after a
            // couple of seconds, then the up-to-date row filters out.
            updatedIndicator

        case .installing(let stage):
            installProgress(stage)

        case .ignored:
            // Surfaced only under "Show all" — a muted tag with manage actions in
            // the context menu, so an ignored app never offers an Update button.
            ignoredTag

        case .versionSkipped:
            skippedTag

        case .relaunchToApplyStaged(let target):
            // The app's own updater already downloaded *the latest* and is waiting to
            // swap it in on the next quit ("Relaunch to update"). Offer the relaunch
            // — never our own Update — so we don't re-download the same bytes or
            // collide with the pending swap.
            relaunchToUpdateButton(target)

        case .restartToApply:
            // Restart is derived from disk-vs-running version, not the remote check,
            // which is why the shared ladder answers it before the status: that keeps
            // the button steady across a refresh's transient `.unknown`, instead of
            // briefly flashing the source hint ("—") until the check finishes.
            restartButton

        case .updateAvailable(let route):
            updateTrailing(route)

        case .checkFailed(let message, let rateLimited):
            errorBadge(message: message, rateLimited: rateLimited)

        case .noSourceCovers:
            Text(sourceHint(for: result)).font(.caption2).foregroundStyle(.tertiary)

        case .managedElsewhere(.appStore):
            appStoreManagedLabel

        case .managedElsewhere(.toolbox):
            toolboxButton

        case .managedElsewhere(.testFlight):
            testFlightManagedLabel

        case .upToDate:
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

    /// How an available update is offered here. The route comes from the model, so
    /// this window and the workbench cannot disagree about whether a row is
    /// one-click — they only differ in how much they explain, which is deliberate.
    @ViewBuilder
    private func updateTrailing(_ route: UpdateRoute) -> some View {
        switch route {
        case .toolbox:
            // Toolbox owns the install. Either Toolbox's own cache detected it, or
            // we borrowed a vendor probe to read the version reliably (Android
            // Studio previews — see `prefersVendorProbeOverToolbox`); either way the
            // action is "open Toolbox", never an in-place swap.
            toolboxButton
        case .testFlight:
            // Detected via TestFlight's cache — it installs, we just route.
            testFlightButton
        case .selfUpdater:
            // Running self-updating app + "defer while running" policy:
            // open its own update path instead of swapping under it.
            openSelfUpdaterButton
        case .majorUpgrade:
            majorUpgradeBadge
        case .autoInstall:
            autoUpdateButton
        case .installer(let stagedFileName):
            installerButton(stagedFileName: stagedFileName)
        case .appStore(let managedHere):
            if let info = result.remote?.appStore {
                appStoreTrailing(info, managedHere: managedHere)
            } else {
                openButton
            }
        case .detectionOnly:
            openButton
        }
    }

    @ViewBuilder
    private func installProgress(_ stage: InstallStage) -> some View {
        if case .downloading(let f) = stage {
            downloadProgress(f)
        } else {
            stageProgress(stage)
        }
    }

    /// The download readout, as wide as the name can afford. Every variant ends
    /// on the row's trailing edge and carries the percentage where there's room
    /// for it — losing the bar costs nothing you can't read off the number, but
    /// losing the number leaves the row saying only "something is happening".
    @ViewBuilder
    private func downloadProgress(_ f: Double) -> some View {
        switch downloadReadout {
        case .barAndPercent:
            HStack(spacing: 4) {
                ProgressView(value: f).frame(width: 50).controlSize(.small)
                percentLabel(f)
            }
            // Centre the bar+label as a tight group in the same minimum-width slot
            // the buttons use, so it lines up down the list. It has to be a
            // *minimum*: the bar plus the percentage is wider than 64pt, and a hard
            // width made the number overflow past the row's trailing edge. The
            // percentage's own fixed width keeps the row from reflowing as it
            // counts up.
            .frame(minWidth: 64, alignment: .center)
        case .ringAndPercent:
            HStack(spacing: 4) {
                ProgressRing(value: f)
                percentLabel(f)
            }
        case .ringOnly:
            // Only for a name long enough that even 32pt of digits would wrap it.
            ProgressRing(value: f)
                .help("Downloading \(result.app.name) — \(Int(f * 100))%")
        }
    }

    /// Fixed-width, right-aligned, monospaced digits: "2%" and "100%" both end at
    /// the same edge, so neither the bar nor the row moves as it counts up.
    /// "100%" at caption2 with monospaced digits measures 28.6pt, so the old 29pt
    /// slot left 0.4pt of slack and SwiftUI wrapped it to "100" over "%". 32pt
    /// gives it real room, and lineLimit+fixedSize make a wrap impossible however
    /// the metrics land.
    private func percentLabel(_ f: Double) -> some View {
        Text("\(Int(f * 100))%")
            .font(.caption2).foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 32, alignment: .trailing)
    }

    /// The non-download stages: a spinner, named where the name column can spare
    /// the width. When it can't, the stage moves into the tooltip.
    @ViewBuilder
    private func stageProgress(_ stage: InstallStage) -> some View {
        if showsStageLabel(stage) {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(installStageLabel(stage))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 64, alignment: .center)
        } else {
            ProgressView().controlSize(.small)
                .help("\(installStageLabel(stage)) \(result.app.name)")
        }
    }


    private var autoUpdateButton: some View {
        Button("Update") { actions.install() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
    }

    /// Muted tag for an app the user has chosen to ignore — right-click to manage.
    /// `ignoredRowLabel()` (in `RowActionViews.swift`) is a catalog key distinct
    /// from the Settings page heading of the same English word — see its doc
    /// comment for why sharing that key here was wrong.
    private var ignoredTag: some View {
        Text(ignoredRowLabel()).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.7)
            .help("Hidden from update checks — right-click to stop ignoring")
    }

    /// Muted tag for an update whose offered version the user skipped.
    private var skippedTag: some View {
        Text(skippedRowLabel()).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.7)
            .help("You skipped this version — right-click to un-skip")
    }

    /// On disk it's current, but the running instance is older — offer a
    /// relaunch so the update actually takes effect.
    private var restartButton: some View {
        Button("Relaunch") { actions.restart() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help(restartHelp)
    }

    /// The bundle is current, but Update All is still busy with other apps and has
    /// not reached its deferred restart phase. Keep an explicit action available so
    /// a slow unrelated installer never makes this completed download look lost.
    private var pendingBatchRestartButton: some View {
        Button("Relaunch now") { actions.restart() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("Installed \(result.app.shortVersion ?? String(localized: "the new version")) — waiting for Update All to finish before relaunching; click to relaunch now")
    }

    /// The app self-downloaded a newer build (Squirrel/ShipIt staged it); a
    /// relaunch swaps it in. Unlike `restartButton` this routes to
    /// `relaunchStagedUpdate`, which quits the app and lets *its own* ShipIt do the
    /// swap+relaunch (reopening it ourselves makes ShipIt abort). No extra download
    /// — the bytes are already staged on disk.
    private func relaunchToUpdateButton(_ target: String) -> some View {
        Button("Relaunch") { actions.relaunchStaged() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(result.app.name) already downloaded \(target) — relaunch to apply it (no extra download; a large app may take a minute to swap & reopen)")
    }

    /// An incremental App Store update is downloaded but the app is running, so the
    /// store wants to quit it to install. Tapping presses the store's Continue (via
    /// the AX installer's awaited `confirmQuit`); the app quits, the update lands,
    /// and we reopen it. Labelled "Relaunch" like every other quit-to-apply action.
    private func quitToFinishButton(_ appName: String) -> some View {
        Button("Relaunch") { actions.confirmQuit() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("\(appName.isEmpty ? result.app.name : appName) must quit to finish updating — click to quit it, install, and reopen")
    }

    /// Shown while a staged relaunch is in flight: the app is quit and its own
    /// ShipIt is swapping the bundle. Matches the install spinner's footprint.
    ///
    /// A spinner rather than a disabled button on purpose: it both signals progress
    /// and, because it REPLACES the button, makes a second click impossible.
    private var relaunchingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Relaunching…")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 64, alignment: .center)
        .help("Quit \(result.app.name) — waiting for it to swap in the new version and reopen")
    }

    private var updatedIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Updated")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 64, alignment: .center)
        .help("\(result.app.name) updated to \(result.app.shortVersion ?? String(localized: "the latest version"))")
    }

    private var restartHelp: String {
        let disk = result.app.shortVersion ?? String(localized: "the new version")
        if let running = runningVersion {
            return String(localized: "Running \(running) but \(disk) is installed — relaunch to apply it")
        }
        return String(localized: "You’re running an older version — relaunch to finish updating")
    }

    /// pkg cask: download the official installer and open it (system installer
    /// asks for admin). Not an in-place swap, so it's a plain bordered button.
    @ViewBuilder
    private func installerButton(stagedFileName: String?) -> some View {
        if let stagedFileName {
            // Already downloaded and handed to macOS's installer. Re-opening costs
            // nothing (and re-uses the installer window if it's still open), so don't
            // make the user pull hundreds of megabytes down a second time because
            // they dismissed it.
            Button("Install") { actions.openStagedPackage() }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help("\(stagedFileName) is already downloaded — opens it in macOS's installer (asks for admin). Nothing is downloaded again.")
        } else {
            Button("Update") { actions.install() }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("Downloads the official installer and opens it (asks for admin)")
        }
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
                actions.install()
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290)
    }

    /// Fallback for updates we can detect but not install in place (GitHub
    /// releases, self-updating apps like Chrome). Opens the official download /
    /// releases page in the browser so the user can grab it through the app's own
    /// channel; only reveals in Finder if there's no URL to open — in which case
    /// the button title says so too (see `DetectionOnlyAffordance`, #197).
    private var openButton: some View {
        Button(openButtonTitle) { openAction() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help(openHelp)
    }

    /// `.openPage`'s title is this host's own call (kept out of
    /// `DetectionOnlyAffordance` on purpose — see its doc comment): the popover
    /// says "Open" here, matching its other single-word action buttons.
    private var openButtonTitle: String {
        switch detectionOnlyAffordance {
        case .openPage: return String(localized: "Open")
        case .revealInFinder: return DetectionOnlyAffordance.revealInFinderTitle
        }
    }

    private var detectionOnlyAffordance: DetectionOnlyAffordance {
        DetectionOnlyAffordance.resolve(pageURL: result.remote?.pageURL)
    }

    /// Shown for a running self-updating app under the "defer while running"
    /// policy: open the app's own update path rather than installing over it.
    private var openSelfUpdaterButton: some View {
        Button("Open") { actions.openSelfUpdater() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("\(result.app.name) is running — open it and let its own updater apply \(result.remote?.displayVersion ?? String(localized: "the update")). Quit it, or pick “Always replace” in Settings, to install directly.")
    }

    private func openAction() {
        guard let url = result.remote?.pageURL else {
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
        Button("Toolbox") { actions.openToolbox() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")
    }


    /// TestFlight manages this beta's updates. There's no per-app deep link we can
    /// rely on, so we just open TestFlight, where the user installs the update
    /// through its own channel.
    private var testFlightButton: some View {
        Button("TestFlight") { actions.openTestFlight() }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Managed by TestFlight — open TestFlight to update \(result.app.name)")
    }


    private var openHelp: String {
        guard let url = result.remote?.pageURL else { return String(localized: "Reveal in Finder") }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            return String(localized: "Open \(result.app.name)’s built-in updater (it updates itself)")
        }
        return String(localized: "Open the official download page")
    }

    /// App Store apps: when the app is in the signed-in region, a Get button
    /// deep-links to the product page; when it isn't, a globe badge opens a
    /// popover explaining the region lock (the store would just say "App Not
    /// Available").
    @ViewBuilder
    private func appStoreTrailing(_ info: AppStoreAvailability, managedHere: Bool) -> some View {
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
        } else if managedHere {
            // Wrapped iPhone/iPad app on the mas route: mas has no Mac-store entry
            // for it, so a one-click here would always fail. Send the user to its
            // product page, where an available update shows an "Update" button.
            //
            // Conditioned on the route rather than inferred from it: this branch is
            // reached whenever `canAutoInstall` is false, which has causes other than
            // the strategy — a declined elevation most of all, and every wrapped app
            // qualifies for one (they sit in a root-owned `/Applications`). Without
            // the check, the button and its "can’t be updated from here" help text
            // would say that on a route where they can.
            Button("App Store") { openInAppStore(info) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help("Update \(result.app.name) in the App Store — iPhone/iPad apps can’t be updated from here")
        } else {
            // A redirect, not a one-click — the App Store route needs the privileged
            // helper approved (`UpdatePolicy.canAutoInstall`, case "App Store"). But
            // the row IS an installed app with a pending update, which the store
            // itself calls **Update**; "Get" reads as "not installed yet", and no row
            // that reaches here ever is. The help text carries the real reason.
            Button("Update") { openInAppStore(info) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help(appStoreRedirectHelp)
        }
    }

    /// Why this row hands off to the App Store instead of installing in place.
    /// Approving the helper is the one lever the user actually has, so name it when
    /// that's what's missing — otherwise the button just looks like something we
    /// decline to do, with nothing to act on.
    private var appStoreRedirectHelp: String {
        if !helperEnabled {
            return String(localized: "Opens \(result.app.name) in the App Store. Turn on the background helper in Settings to install App Store updates in one click.")
        }
        return String(localized: "Update \(result.app.name) in the App Store")
    }

    private func openInAppStore(_ info: AppStoreAvailability) {
        if let url = info.deepLink ?? result.remote?.pageURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func regionHintPopover(_ info: AppStoreAvailability) -> some View {
        let here = info.homeRegion.map(Self.regionName) ?? String(localized: "your region")
        let there = Self.regionName(info.availableRegion)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Region-locked", systemImage: "globe.badge.chevron.backward")
                .font(.headline)
            Text("\(result.app.name) isn’t in your App Store region (\(here)). It’s listed in \(there)\(result.remote?.displayVersion.map { String(localized: " — latest \($0)") } ?? "").")
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
                    actions.install()
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
            Text("You can keep using the installed version (\(result.app.shortVersion ?? String(localized: "current"))). Updating isn't possible until the developer ships a Mac-compatible build again — it's the vendor's choice, not a refresh problem.")
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
        Image(nsImage: AppIconCache.appStore)
            .resizable()
            .frame(width: 16, height: 16)
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
    private func errorBadge(message: String, rateLimited: Bool) -> some View {
        HStack(spacing: 6) {
            // Name the failure inline so a wall of orange retry buttons isn't
            // indistinguishable — a rate-limit (the common no-token case) reads
            // differently from a one-off network error without needing a hover.
            let statusLabel = rateLimited
                ? String(localized: "Rate-limited")
                : String(localized: "Failed")
            Text(statusLabel)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(rateLimited ? Color.orange : Color.secondary)
            Button { actions.retry() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help(message.isEmpty
                ? String(localized: "Update check failed — click to retry")
                : String(localized: "\(message) — click to retry"))
        }
    }

}
