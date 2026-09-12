import SwiftUI
import DuoUpdaterCore

/// The word shown beside an install spinner. Shared: `AppRow` needs it to decide
/// whether the label fits beside the name, and both action views need it to draw.
/// What a row with no covering source says instead of an action. Shared, because
/// the two windows used to disagree: the popover named the source it knows about
/// ("App Store", "Sparkle") while the workbench always drew a bare em dash, so the
/// same state read as two different things depending on which window you opened.
///
/// Takes the `SourceHint` the state now carries rather than reading
/// `result.app.isMASApp` / `sparkleFeedURL` itself — that was the last place
/// either view still formed its own opinion about what to name (issue #260); the
/// priority between App Store and Sparkle now lives in `RowAction.state`.
func sourceHint(for hint: SourceHint) -> String {
    switch hint {
    case .none: return "—"
    case .appStore: return String(localized: "App Store")
    case .sparkle: return String(localized: "Sparkle")
    }
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

/// Muted tag for a row hidden from update checks. A distinct catalog key from
/// `SettingsSection.label` (case `.ignored`) on purpose: that one is a **plural**
/// page heading ("Ignored" apps), and several languages translated it as such
/// (es "Ignoradas", fr "Ignorées", ru "Игнорируемые" — all plural). Sharing that
/// key here read as a plural describing the single app on this row. Shared
/// between this file and `PopoverRowAction`, same reasoning as `sourceHint`.
func ignoredRowLabel() -> String {
    String(localized: "Ignored (row status)", defaultValue: "Ignored",
           comment: "Muted tag on a single row for an app hidden from update checks. Keep this singular — it is not the plural Settings page heading of the same English word.")
}

/// Muted tag for a row whose offered version the user skipped. A distinct key
/// from the popover's original value, which carried a disambiguating
/// parenthetical sized for a tiny `.caption2` tag (fr: "Ignoré (version)") that
/// reads oddly once also drawn at the workbench's larger `.callout`.
func skippedRowLabel() -> String {
    String(localized: "Skipped (row status)", defaultValue: "Skipped",
           comment: "Muted tag on a single row for a version the user skipped — short, standalone, no parenthetical qualifier.")
}

/// The row actions both windows can trigger, as plain closures.
///
/// The views below take these rather than an `AppListModel`, which is what makes
/// them renderable with no model at all — the property `RowStateGallery` relies on
/// to draw every `RowActionState` into a reference image. Defaults are no-ops, so a
/// gallery or preview supplies only what it wants to observe.
struct RowActions {
    /// Every action defaults to a no-op so a gallery or preview can supply only
    /// what it wants to observe. That convenience is also a trap for the two real
    /// windows: a construction site that omits one compiles fine and ships a button
    /// that does nothing. It has happened once already — the workbench's literal
    /// ended at `openToolbox`, so `openTestFlight` was silently dead — which is why
    /// `live(...)` exists. **The two windows must build their actions through it**,
    /// so adding a tenth action breaks the build at both sites instead of going
    /// quiet at whichever one was forgotten.
    var install: () -> Void = {}
    var openStagedPackage: () -> Void = {}
    var retry: () -> Void = {}
    var restart: () -> Void = {}
    var relaunchStaged: () -> Void = {}
    var confirmQuit: () -> Void = {}
    var openSelfUpdater: () -> Void = {}
    var openToolbox: () -> Void = {}
    var openTestFlight: () -> Void = {}
    var grantFullDiskAccess: () -> Void = {}
    /// Deep-link to Settings → General, where TestFlight detection is. Only the
    /// "checking is off" tip offers it, and it is an action rather than a sentence
    /// pointing at a menu for the same reason `grantFullDiskAccess` is: the row is
    /// where the user is, and the way out of the state should be one click from
    /// there.
    var openTestFlightSetting: () -> Void = {}

    /// The full set, with no defaults — for a real window, where a missing action
    /// is a dead control rather than a deliberate omission.
    static func live(
        install: @escaping () -> Void,
        openStagedPackage: @escaping () -> Void,
        retry: @escaping () -> Void,
        restart: @escaping () -> Void,
        relaunchStaged: @escaping () -> Void,
        confirmQuit: @escaping () -> Void,
        openSelfUpdater: @escaping () -> Void,
        openToolbox: @escaping () -> Void,
        openTestFlight: @escaping () -> Void,
        grantFullDiskAccess: @escaping () -> Void,
        openTestFlightSetting: @escaping () -> Void
    ) -> RowActions {
        RowActions(
            install: install, openStagedPackage: openStagedPackage, retry: retry,
            restart: restart, relaunchStaged: relaunchStaged, confirmQuit: confirmQuit,
            openSelfUpdater: openSelfUpdater, openToolbox: openToolbox,
            openTestFlight: openTestFlight, grantFullDiskAccess: grantFullDiskAccess,
            openTestFlightSetting: openTestFlightSetting)
    }
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
    /// Why a TestFlight row cannot bound its beta — decides which mark it carries
    /// and what that mark explains (`TestFlightUnboundedReason`). An input for the
    /// same reason as `helperEnabled`.
    var testFlightUnboundedReason: TestFlightUnboundedReason = .storeSilent

    @State private var showTestFlightTip = false

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
            Text(ignoredRowLabel()).font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .help("Hidden from update checks — right-click to stop ignoring")

        case .versionSkipped:
            Text(skippedRowLabel()).font(.callout).foregroundStyle(.tertiary)
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

        case .noSourceCovers(let hint):
            Text(sourceHint(for: hint)).font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1)

        case .managedElsewhere(.appStore):
            appStoreManagedTile

        case .managedElsewhere(.toolbox):
            Button("Toolbox") { actions.openToolbox() }
                .buttonStyle(.bordered)
                .help("Managed by JetBrains Toolbox — open Toolbox to update \(result.app.name)")

        case .managedElsewhere(.testFlight):
            testFlightUnboundedTile

        case .upToDate(let channel):
            // Blank is deliberate for `.none` (`mayBeBlank` in the gallery says
            // so); a store-managed or TestFlight app keeps naming its channel so
            // it never reads like something we could update ourselves, matching
            // the popover's `.managedElsewhere` tiles rather than repeating them.
            switch channel {
            case .none: EmptyView()
            case .appStore: appStoreManagedTile
            case .testFlight: testFlightManagedTile
            }
        }
    }

    /// Shared between `.managedElsewhere(.appStore)` and a current row that keeps
    /// naming the App Store (`.upToDate(channel: .appStore)`) — same tile either
    /// way, since updates are the store's job in both.
    private var appStoreManagedTile: some View {
        Image(nsImage: AppIconCache.appStore)
            .resizable().frame(width: 16, height: 16)
            .help("Managed by the App Store — it handles this app's updates")
    }

    /// A current row that keeps naming TestFlight (`.upToDate(channel: .testFlight)`).
    /// `.managedElsewhere(.testFlight)` used to share it; `testFlightUnboundedTile`
    /// says why it no longer does.
    ///
    /// TestFlight's own icon, matching `appStoreManagedTile` above and the
    /// popover's tag for the same state; the word is the fallback for a Mac with
    /// no TestFlight installed, where there is no icon to draw.
    @ViewBuilder
    private var testFlightManagedTile: some View {
        if let icon = AppIconCache.testFlight {
            Image(nsImage: icon)
                .resizable().frame(width: 16, height: 16)
                // Same reasoning as the popover's tag: `.help` is a hint, not a
                // name, so the image needs its own label to stay audible.
                .accessibilityLabel("TestFlight")
                .help("Managed by TestFlight — it handles this beta's updates")
        } else {
            Text("TestFlight").font(.callout).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .help("Managed by TestFlight — it handles this beta's updates")
        }
    }

    /// `.managedElsewhere(.testFlight)` — the popover's `testFlightUnboundedLabel`
    /// explains the state; this is the same mark at this surface's size.
    @ViewBuilder
    private var testFlightUnboundedTile: some View {
        Group {
            if let icon = AppIconCache.testFlight {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Text("TestFlight").font(.callout).foregroundStyle(.tertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .dimmedWhenOff(testFlightUnboundedReason)
        .overlay(alignment: .bottomTrailing) {
            TestFlightUnboundedMark(reason: testFlightUnboundedReason).offset(x: 4, y: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TestFlight")
        .help(testFlightUnboundedReason.rowHelp)
        // A tap, not a Button: see `TestFlightUnboundedMark` on why this mark stays
        // out of a borderless button.
        .contentShape(Rectangle())
        .onTapGesture { showTestFlightTip = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showTestFlightTip = true }
        .popover(isPresented: $showTestFlightTip, arrowEdge: .bottom) {
            TestFlightUnboundedTip(
                reason: testFlightUnboundedReason, grant: actions.grantFullDiskAccess,
                openSetting: actions.openTestFlightSetting)
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

        case .appStore(let storeManagedHere, let gate):
            // Which of the three pictures below applies comes from the route's
            // `gate`, not from re-reading `result.remote?.appStore` here — that
            // used to be exactly how this branch decided (issue #260), which is
            // also why it used to collapse both gates into one identical Label:
            // nothing forced the two windows' branch conditions to agree, only
            // their content did. `info` below is read for display text only
            // (a deep link, a version number), never to choose a branch.
            let info = result.remote?.appStore
            switch gate {
            case .macIncompatible:
                // The popover explains this in a popover of its own; this window
                // names the gate and stays out of the way. Same title the popover
                // uses for its explanation, so the two cannot describe the same
                // row differently.
                //
                // `.lineLimit(1).minimumScaleFactor(0.7)` added alongside
                // `.needsNewerMacOS` below (#546 review): this case's own
                // German translation ("Auf diesem Mac nicht unterstützt", 32
                // characters) had no overflow protection at all before —
                // CLAUDE.md's own recorded lesson about copying a popover
                // label into the workbench without it.
                Label("Not supported on this Mac", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .help("The latest version no longer supports this Mac — click for details")
            case .needsNewerMacOS(let minimum):
                // Same title/help the popover's badge uses, so the two windows
                // never describe the same row differently — see the doc
                // comment on the `.macIncompatible` case above.
                Label("Needs a newer macOS", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .help("Requires macOS \(minimum) or later — click for details")
            case .region:
                Label("Region-locked", systemImage: "globe.badge.chevron.backward")
                    .font(.callout).foregroundStyle(.orange)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .help("Not available in your App Store region — click for details")
            case .none:
                // A wrapped iPhone/iPad app on the mas route: mas has no Mac-store
                // entry for it, so this is a redirect rather than a one-click. A
                // Mac App Store app lands here when the privileged helper isn't
                // approved yet — still an installed app with a pending update, so
                // it says **Update** (what the store calls it), never "Get".
                Button(storeManagedHere ? String(localized: "App Store") : String(localized: "Update")) {
                    if let url = info?.deepLink ?? result.remote?.pageURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
                .help(storeManagedHere
                      ? String(localized: "Update \(result.app.name) in the App Store — iPhone/iPad apps can’t be updated from here")
                      : appStoreRedirectHelp)
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
/// silently degrades to the narrowest option, with no compile error — and the
/// algorithm itself is in `AppRow`, which `DuoUpdaterAppTests` does not compile
/// (that target builds only the files `App/project.yml` names). What holds the
/// order is the gallery: tiles 35 and 36 draw `.ringAndPercent` and `.ringOnly`
/// (via `RowStateGalleryCases.popoverDownloadReadoutOverrides`), and
/// `RowStateGalleryCases.downloadReadoutOrderIsIntact()` fails the build outright
/// if this declaration order changes — because an image diff is a symptom, not an
/// assertion.
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

/// The mark on a TestFlight row whose store could not bound it. One view for both
/// surfaces, so the popover and the workbench cannot drift into two different
/// marks for one state.
///
/// Two symbols, because the row has two things to say and they are not the same
/// thing. A question mark means *asked, and could not be told* — the store was
/// read and had no answer, or the permission to read it is missing. With detection
/// off nothing was asked at all, and a question mark there reads as a failure the
/// user should go and fix, which is how someone ends up granting Full Disk Access
/// for a read that will still not happen (#547). That state gets a slash.
///
/// ⚠️ **The badge alone does not carry this.** It was a `minus.circle.fill` first,
/// and the person who asked for the setting misread the shipped build as a
/// question mark — at 9pt a dash inside a filled circle has very nearly the
/// silhouette of a "?", and telling the two states apart is the entire job. So the
/// glyph is a slash, which differs in direction rather than in fine detail, and
/// `dimmedWhenOff` mutes the icon under it: at this size the reliable signal is the
/// 16pt icon changing, not the 9pt badge. Neither half is decoration — a change
/// that drops one of them puts the state back where it was misread.
///
/// Not inside a button on purpose: `ImageRenderer` draws an SF Symbol in a
/// borderless button as a placeholder, and the gallery would then have to
/// list this state as unfaithful.
struct TestFlightUnboundedMark: View {
    var reason: TestFlightUnboundedReason = .storeSilent

    var body: some View {
        Image(systemName: reason == .checkingOff ? "slash.circle.fill" : "questionmark.circle.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .background(Circle().fill(.background).padding(1))
    }
}

extension View {
    /// Mute a TestFlight row's icon when nothing is checking it — the other half of
    /// `TestFlightUnboundedMark`, applied to the mark's host rather than living
    /// inside it because it is the ICON that has to change, not the badge.
    ///
    /// Grayscale and half opacity: the same "this is switched off" idiom macOS uses
    /// for a disabled control, and a change big enough to read from across the row.
    /// Deliberately not applied to the other two reasons — those rows ARE being
    /// checked, and dimming them would say the opposite of what is true.
    @ViewBuilder func dimmedWhenOff(_ reason: TestFlightUnboundedReason) -> some View {
        if reason == .checkingOff {
            self.grayscale(1).opacity(0.5)
        } else {
            self
        }
    }
}

extension TestFlightUnboundedReason {
    /// The row's own tooltip — the whole sentence, since a pointer never gets the
    /// tip that a tap opens. Three whole sentences rather than one assembled from
    /// parts, so each is a key the catalog carries and can be translated as a
    /// sentence.
    ///
    /// A `String(localized:)` rather than a `Text`: the gallery's tooltip check
    /// reflects the view tree for the string a `.help` carries, and this is the one
    /// `.help` in the app whose text is computed rather than written at the call
    /// site (`main.swift`'s `collectHelpTexts`).
    var rowHelp: String {
        switch self {
        case .checkingOff:
            return String(localized: "TestFlight checking is off, so Duo Updater can’t say whether this beta is current")
        case .noFullDiskAccess:
            return String(localized: "Duo Updater has no Full Disk Access to read the builds TestFlight offers you, so it can’t say whether this beta is current")
        case .storeSilent:
            return String(localized: "TestFlight hasn’t told us this beta’s latest build, so we can’t say whether it’s current")
        }
    }
}

/// What tapping that mark opens, in both windows: why the row cannot say whether
/// the beta is current, and — when the reason is a missing Full Disk Access — the
/// way to grant it. Shared so the two windows cannot explain one state two ways.
/// A literal `Text` per case rather than a value built from parts, which could
/// resolve to `String` and skip localization.
///
/// Two of the three reasons carry a way out, and it is a different way out each
/// time: a missing permission is granted, a switched-off setting is switched on.
/// Offering Grant… for the second would send the user to a permission that changes
/// nothing while the setting is off. `storeSilent` gets no button because there is
/// nothing to open — Refresh, which the sentence names, is already on screen.
struct TestFlightUnboundedTip: View {
    let reason: TestFlightUnboundedReason
    let grant: () -> Void
    var openSetting: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private var fullDiskAccessMissing: Bool { reason == .noFullDiskAccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                switch reason {
                case .checkingOff:
                    Text("Duo Updater isn’t checking TestFlight betas. Turn it on in Settings → General to see whether this beta is current.")
                case .noFullDiskAccess:
                    Text("Without Full Disk Access, Duo Updater can’t read the builds TestFlight offers you, so it can’t say whether this beta is current.")
                case .storeSilent:
                    Text("TestFlight hasn’t told Duo Updater this beta’s latest build yet. Refreshing asks TestFlight to check.")
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            // Trailing, where macOS puts the action in a dialog or popover.
            if fullDiskAccessMissing {
                HStack {
                    Spacer()
                    Button("Grant…") {
                        dismiss()
                        grant()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else if reason == .checkingOff {
                HStack {
                    Spacer()
                    Button("Settings…") {
                        dismiss()
                        openSetting()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}

/// The name-line mark for a row whose answer may be missing something only Full
/// Disk Access could read (`AppListModel.fullDiskAccessNeedsAffecting`). Draws
/// nothing when there is no such read. Tapping it explains which read and offers
/// the grant; a tap rather than a Button for the same reason as
/// `TestFlightUnboundedMark`.
struct FullDiskAccessMark: View {
    let needs: [FullDiskAccessNeed]
    let grant: () -> Void
    var size: CGFloat = 11

    @State private var showTip = false

    /// The width it claims on the name line, for rows that budget their width
    /// before layout (the same job as `ChannelTag.measuredWidth`). Matches the
    /// `.frame` in `body`.
    static func width(size: CGFloat = 11) -> CGFloat { size + 2 }

    var body: some View {
        if !needs.isEmpty {
            Image(systemName: "lock.circle")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .frame(width: Self.width(size: size))
                .contentShape(Rectangle())
                .onTapGesture { showTip = true }
                .help("Checked without Full Disk Access — click for why")
                .accessibilityLabel("Full Disk Access needed")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showTip = true }
                .popover(isPresented: $showTip, arrowEdge: .bottom) {
                    FullDiskAccessTip(needs: needs, grant: grant)
                }
        }
    }
}

/// What that mark opens: one sentence per read turned away, and the grant.
struct FullDiskAccessTip: View {
    let needs: [FullDiskAccessNeed]
    let grant: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(needs, id: \.self) { need in
                Self.reason(need)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Grant…") {
                    dismiss()
                    grant()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    /// A switch, so a read added to `FullDiskAccessNeed` cannot reach this tip
    /// without saying what the missing grant costs.
    @ViewBuilder
    static func reason(_ need: FullDiskAccessNeed) -> some View {
        switch need {
        case .testFlight:
            Text("Without Full Disk Access, Duo Updater can’t read the builds TestFlight offers you, so it can’t say whether this beta is current.")
        case .cotEditorChannel:
            Text("Without Full Disk Access, Duo Updater can’t see whether you chose prereleases in CotEditor, so only its stable releases are offered.")
        }
    }
}
