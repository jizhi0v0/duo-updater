import SwiftUI
import DuoUpdaterCore

/// The word shown beside an install spinner. Shared: `AppRow` needs it to decide
/// whether the label fits beside the name, and both action views need it to draw.
/// What a row with no covering source says instead of an action. Shared, because
/// the two windows used to disagree: the popover named the source it knows about
/// ("App Store", "Sparkle") while the workbench always drew a bare em dash, so the
/// same state read as two different things depending on which window you opened.
///
/// It reads the ROW rather than the state, which is the last place either view
/// still forms its own opinion — see `RowActionState`. Shared here so that opinion
/// is at least a single one.
func sourceHint(for result: UpdateResult) -> String {
    if result.app.isMASApp { return String(localized: "App Store") }
    if result.app.sparkleFeedURL != nil { return String(localized: "Sparkle") }
    return "—"
}

func installStageLabel(_ stage: InstallStage) -> String {
    switch stage {
    case .queued: return String(localized: "Queued")
    case .checking: return String(localized: "Checking")
    case .downloading(let f): return String(localized: "\(Int(f * 100))%")
    case .verifyingSignature, .verifyingCodeSignature: return String(localized: "Verifying")
    case .extracting: return String(localized: "Extracting")
    case .installing: return String(localized: "Installing")
    case .runningCommand: return String(localized: "Installing")
    case .done: return String(localized: "Installed")
    }
}

/// The row actions both windows can trigger, as plain closures.
///
/// The views below take these rather than an `AppListModel`, which is what makes
/// them renderable with no model at all — the property `RowStateGallery` relies on
/// to draw every `RowActionState` into a reference image. Defaults are no-ops, so a
/// gallery or preview supplies only what it wants to observe.
struct RowActions {
    var install: () -> Void = {}
    var openStagedPackage: () -> Void = {}
    var retry: () -> Void = {}
    var restart: () -> Void = {}
    var relaunchStaged: () -> Void = {}
    var confirmQuit: () -> Void = {}
    var openSelfUpdater: () -> Void = {}
    var openToolbox: () -> Void = {}
    var openTestFlight: () -> Void = {}
}

struct WorkbenchRowAction: View {
    let state: RowActionState
    let result: UpdateResult
    var actions: RowActions = .init()
    /// Whether the privileged helper is approved. Only affects an App Store row's
    /// help text; carried as an input so this view stays a pure function of what it
    /// is given (which is what lets `RowStateGallery` render every case with no
    /// model at all).
    var helperEnabled: Bool = true

    var body: some View {
        // `ui = f(state)`. The ladder that decides WHICH of these applies lives in
        // `RowAction.state`, shared with the popover, so the two windows cannot
        // disagree about what a row is — they used to, most visibly during an App
        // Store install waiting on a quit (the popover showed the prompt, this
        // showed a progress bar).
        //
        // Every state has a branch. A row that draws nothing here must be a row
        // that genuinely has nothing to say (`upToDate`); "the surface had no case
        // for what this is" used to look identical to "all good", in a window whose
        // other rows carry an Update button.
        switch state {
        case .awaitingQuitConfirm(let appName):
            Button("Relaunch") { actions.confirmQuit() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("\(appName.isEmpty ? result.app.name : appName) must quit to finish updating — click to quit it, install, and reopen")

        case .relaunching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Relaunching…").font(.callout).foregroundStyle(.secondary)
            }

        case .pendingBatchRestart:
            Button("Relaunch now") { actions.restart() }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("The update is installed; Update All is waiting to relaunch apps until the batch finishes")

        case .justUpdated:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Updated").font(.callout).foregroundStyle(.secondary)
            }

        case .installing(let stage):
            installProgress(stage)

        case .ignored:
            Text("Ignored").font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .help("Hidden from update checks — right-click to stop ignoring")

        case .versionSkipped:
            Text("Skipped").font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .help("You skipped this version — right-click to un-skip")

        case .relaunchToApplyStaged(let target):
            Button("Relaunch") { actions.relaunchStaged() }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("\(result.app.name) already downloaded \(target) — relaunch to apply it")

        case .restartToApply:
            Button("Relaunch") { actions.restart() }
                .buttonStyle(.bordered)
                .tint(.orange)
                .help("Running an older build — relaunch to apply the installed update")

        case .updateAvailable(let route):
            updateAction(route)

        case .checkFailed(let message, let rateLimited):
            // Was rendered as NOTHING here, which reads as "up to date" in a window
            // that shows an Update button whenever there is one. Same wording and
            // same Retry as the popover's badge, so the two agree.
            HStack(spacing: 8) {
                Text(rateLimited
                     ? String(localized: "Rate-limited")
                     : String(localized: "Failed"))
                    .font(.callout)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(rateLimited ? Color.orange : Color.secondary)
                Button { actions.retry() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(message.isEmpty
                      ? String(localized: "Update check failed — click to retry")
                      : String(localized: "\(message) — click to retry"))
            }

        case .noSourceCovers:
            Text(sourceHint(for: result)).font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1)

        case .managedElsewhere(.appStore):
            Image(nsImage: AppIconCache.appStore)
                .resizable().frame(width: 16, height: 16)
                .help("Managed by the App Store — it handles this app's updates")

        case .managedElsewhere(.toolbox):
            Button("Toolbox") { actions.openToolbox() }
                .buttonStyle(.bordered)
                .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")

        case .managedElsewhere(.testFlight):
            Text("TestFlight").font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .help("Managed by TestFlight — it handles this beta's updates")

        case .upToDate:
            EmptyView()
        }
    }

    /// The install action for an actionable update, mirroring the popover's routing
    /// for the one-click-safe cases. Major upgrades and region/compat-gated App Store
    /// apps are intentionally NOT one-click here — they keep their explanatory
    /// popover affordances in the menu bar — so we show a hint that points there.
    @ViewBuilder
    private func updateAction(_ route: UpdateRoute) -> some View {
        // The route was resolved by the model, not re-derived here, so this window
        // and the popover cannot disagree about whether a row is one-click.
        //
        // Presentation still differs on purpose for the two gated routes: a major
        // upgrade may cross a paid-licence boundary and an App Store row may be
        // region-locked, and the explanation that makes either safe to act on lives
        // in the popover. This window names the state and points there rather than
        // offering a bare button — which is NOT the same as rendering nothing, the
        // failure this whole type exists to remove.
        switch route {
        case .toolbox:
            Button("Toolbox") { actions.openToolbox() }
                .buttonStyle(.bordered)
                .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")

        case .testFlight:
            Button("TestFlight") { actions.openTestFlight() }
                .buttonStyle(.bordered)
                .help("Managed by TestFlight — open TestFlight to update \(result.app.name)")

        case .selfUpdater:
            // Running self-updating app + "defer while running" policy: open
            // its own update path rather than swapping the bundle under it.
            Button("Open") { actions.openSelfUpdater() }
                .buttonStyle(.bordered)
                .help("\(result.app.name) is running — open it so its own updater applies the update. Quit it, or pick “Always replace” in Settings, to install directly.")

        case .majorUpgrade:
            // License-boundary warning lives in the popover; don't one-click it here.
            Label("Major update", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
                .help("Major version upgrade — review and install it from the menu-bar popover")

        case .autoInstall:
            Button("Update \(result.remote?.displayVersion ?? "")") { actions.install() }
                .buttonStyle(.borderedProminent)
                .help("Download and install \(result.app.name) \(result.remote?.displayVersion ?? "")")

        case .installer(let stagedFileName):
            // Already downloaded → "Install" re-opens that exact package instead of
            // fetching it again. See `AppListModel.stagedPackage(for:)`.
            if let stagedFileName {
                Button("Install") { actions.openStagedPackage() }
                    .buttonStyle(.borderedProminent)
                    .help("\(stagedFileName) is already downloaded — opens it in macOS's installer (asks for admin). Nothing is downloaded again.")
            } else {
                Button("Update") { actions.install() }
                    .buttonStyle(.bordered)
                    .help("Downloads the official installer and opens it (asks for admin)")
            }

        case .appStore(let storeManagedHere):
            // A wrapped iPhone/iPad app on the mas route: mas has no Mac-store entry
            // for it, so this is a redirect rather than a one-click. A Mac App Store
            // app lands here when the privileged helper isn't approved yet — still an
            // installed app with a pending update, so it says **Update** (what the
            // store calls it), never "Get".
            //
            // A region-locked or OS-incompatible listing used to fall through to the
            // detection-only tail, which said "Open page" and explained nothing. It
            // now says why, and sends the user to the popover that can.
            if let info = result.remote?.appStore, !info.isRegionMismatch, !info.isLatestMacIncompatible {
                Button(storeManagedHere ? String(localized: "App Store") : String(localized: "Update")) {
                    if let url = info.deepLink ?? result.remote?.pageURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
                .help(storeManagedHere
                      ? String(localized: "Update \(result.app.name) in the App Store — iPhone/iPad apps can’t be updated from here")
                      : appStoreRedirectHelp)
            } else {
                // The popover explains these two in a popover of their own; this
                // window names the gate and stays out of the way. Same strings, so
                // the two windows cannot describe the same row differently.
                Label("App Store", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .help(result.remote?.appStore?.isLatestMacIncompatible == true
                          ? String(localized: "The latest version no longer supports this Mac — click for details")
                          : String(localized: "Not available in your App Store region — click for details"))
            }

        case .detectionOnly:
            // No artifact, no vendorInstallerKind, no App Store route. Mirror the
            // popover's fallback instead of rendering nothing when there's no page
            // either — see `DetectionOnlyAffordance` (#197). The title for
            // `.openPage` is this host's own call (kept out of the shared type on
            // purpose): "Open page" here, distinct from the popover's "Open".
            let affordance = DetectionOnlyAffordance.resolve(pageURL: result.remote?.pageURL)
            let title = affordance == .revealInFinder
                ? DetectionOnlyAffordance.revealInFinderTitle
                : String(localized: "Open page")
            Button(title) {
                switch affordance {
                case .openPage(let url):
                    // Unlike the popover's openAction(), this always does a
                    // plain open — it does not check for a non-http(s) scheme
                    // and hand it to the app itself via `withApplicationAt:`.
                    // Pre-existing gap, out of scope for #197.
                    NSWorkspace.shared.open(url)
                case .revealInFinder:
                    NSWorkspace.shared.activateFileViewerSelecting([result.app.path])
                }
            }
            .buttonStyle(.bordered)
            .help(affordance == .revealInFinder
                  ? DetectionOnlyAffordance.revealInFinderTitle
                  : String(localized: "Open the official download page"))
        }
    }

    /// Why this row hands off to the App Store instead of installing in place —
    /// same reasoning as the popover's: approving the helper is the one lever the
    /// user has, so say so when that's what's missing.
    private var appStoreRedirectHelp: String {
        if !helperEnabled {
            return String(localized: "Opens \(result.app.name) in the App Store. Turn on the background helper in Settings to install App Store updates in one click.")
        }
        return String(localized: "Update \(result.app.name) in the App Store")
    }

    @ViewBuilder
    private func installProgress(_ stage: InstallStage) -> some View {
        HStack(spacing: 8) {
            if case .downloading(let f) = stage {
                ProgressView(value: f).frame(width: 80).controlSize(.small)
                Text("\(Int(f * 100))%")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit().frame(width: 40, alignment: .trailing)
            } else {
                ProgressView().controlSize(.small)
                Text(installStageLabel(stage)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

}

/// The readouts a downloading row can wear, WIDEST FIRST — `AppRow` walks
/// `allCases` in order and takes the first one the app's name leaves room for, so
/// the declaration order is the algorithm. Reorder these and every downloading row
/// silently degrades to the narrowest option: no compile error, no test (there is
/// no test target over `App/Sources`), and no gallery tile, since the gallery draws
/// only the default.
///
/// The widths are what the group actually lays out to: the indicator, the 4pt
/// HStack spacing, and the percentage's fixed 32pt slot.
///
/// Not private: the popover row action was extracted to its own file (so the
/// gallery can draw it), and this is a layout decision the ROW makes and hands down.
enum DownloadReadout: CaseIterable {
    case barAndPercent      // 86pt
    case ringAndPercent     // 51pt
    case ringOnly           // 15pt

    static let bar: CGFloat = 50
    static let ring: CGFloat = 15
    static let spinner: CGFloat = 16
    static let percent: CGFloat = 32

    var contentWidth: CGFloat {
        switch self {
        case .barAndPercent: Self.bar + 4 + Self.percent
        case .ringAndPercent: Self.ring + 4 + Self.percent
        case .ringOnly: Self.ring
        }
    }
}

/// A determinate progress ring, 15pt across — the compact stand-in for the
/// bar-plus-percentage readout on rows whose name needs the horizontal space.
///
/// Drawn rather than borrowed from `ProgressView(value:).progressViewStyle(.circular)`
/// so the diameter and the tint are ours to fix at the size the row can afford.
/// The floor on `trim` keeps a just-started download visibly a ring rather than
/// a bare grey circle.
struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}
