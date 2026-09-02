import AppKit
import Foundation
import SwiftUI
import DuoUpdaterCore

/// Every state the gallery draws, named so the PNGs sort into a readable sheet.
///
/// Deliberately exhaustive and written out by hand rather than derived: the point
/// is to notice when a NEW state is added and nobody drew it, which a derivation
/// from the enum would paper over by rendering it automatically.
enum RowStateGalleryCases {
    private static let installed = InstalledApp(
        name: "Example", bundleID: "com.example.app",
        shortVersion: "1.2.3", buildVersion: "1230",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        isMASApp: false, sparkleFeedURL: nil)

    private static func result(
        app: InstalledApp = installed,
        appStore: AppStoreAvailability? = nil
    ) -> UpdateResult {
        UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: "1.3.0", version: "1300",
                downloadURL: URL(string: "https://example.com/Example.dmg"),
                pageURL: URL(string: "https://example.com/download"),
                downloadSize: 12_000_000,
                sourceName: "Sparkle",
                appStore: appStore),
            status: .updateAvailable(latest: "1.3.0"))
    }

    /// The plain row every state uses unless it needs something more specific.
    static let app = result()

    // The App Store branches are the reason these exist. A single fixture with
    // `remote.appStore == nil` sent EVERY App Store state down `openButton`, so
    // three tiles rendered byte-identically and `appStoreTrailing` — region hint,
    // Mac-compat hint, the redirect button — was never drawn at all. The gallery
    // still passed its blank check, because it was measuring the fixture rather
    // than the code. Same trap the language harness hit in 2026-09 feeding
    // `remote: nil` and screenshotting a wall of "Reveal in Finder".
    static let storeApp = result(appStore: AppStoreAvailability(
        trackID: 497799835, availableRegion: "us", homeRegion: "us"))
    static let storeRegionLocked = result(appStore: AppStoreAvailability(
        trackID: 497799835, availableRegion: "cn", homeRegion: "us"))
    static let storeMacIncompatible = result(appStore: AppStoreAvailability(
        trackID: 497799835, availableRegion: "us", homeRegion: "us",
        latestMacCompatible: false))

    /// The two windows, each drawing the same states. `AnyView` because they are
    /// different types; the gallery only needs "draw this state". Takes the case
    /// NAME as well as the state/row now (not just for the two windows to differ,
    /// but so `popoverTile` can special-case the three explanation-content names
    /// below and `workbenchTile` can recognize them too).
    @MainActor
    static let surfaces: [(String, (String, RowActionState, UpdateResult) -> AnyView)] = [
        ("popover", popoverTile),
        ("workbench", workbenchTile),
    ]

    /// Every case except the three explanation-content ones (38–40) draws
    /// `PopoverRowAction` at the row's normal 320×44 slot, with the readout/stage
    /// overrides above applied where a case names one. The explanation cases draw
    /// the popover's own content view instead, sized to itself (`.fixedSize()`) —
    /// it already carries its own `.frame(width:)`/`.padding()`, and forcing it
    /// into a 44pt-tall row slot would clip the paragraph.
    @MainActor
    private static func popoverTile(name: String, state: RowActionState, result: UpdateResult) -> AnyView {
        switch name {
        case "38-major-upgrade-explanation":
            return AnyView(
                PopoverRowAction(state: state, result: result).majorUpgradePopover.fixedSize())
        case "39-region-hint-explanation", "40-mac-compat-hint-explanation":
            // Both read the row's own App Store info — same source the real badge
            // uses to pick which popover to open (`appStoreTrailing`).
            guard let info = result.remote?.appStore else {
                // Cannot happen for the two fixtures these names are paired with in
                // `all` (both carry `appStore`) — a mismatch here would be a bug in
                // this file, not a state the gallery should render as if it were
                // fine, hence `unrendered` rather than a placeholder.
                return AnyView(EmptyView())
            }
            let popover = PopoverRowAction(state: state, result: result)
            return AnyView(
                (name == "39-region-hint-explanation"
                    ? AnyView(popover.regionHintPopover(info))
                    : AnyView(popover.macCompatHintPopover(info)))
                .fixedSize())
        default:
            return AnyView(
                PopoverRowAction(
                    state: state, result: result,
                    downloadReadout: popoverDownloadReadoutOverrides[name] ?? .barAndPercent,
                    showsStageLabel: popoverShowsStageLabelOverrides[name] ?? { _ in true })
                .frame(width: 320, height: 44, alignment: .trailing))
        }
    }

    /// The workbench has no equivalent of "open the popover's explanation panel" —
    /// it points at the popover for that (see the file-level doc comment on
    /// `PopoverRowAction`) — so it draws `EmptyView` for those three names rather
    /// than silently repeating case 18/21/22's tile under a new name. That EmptyView
    /// is registered in `mayBeBlank`, the same way `.upToDate`'s three workbench
    /// tiles already are.
    @MainActor
    private static func workbenchTile(name: String, state: RowActionState, result: UpdateResult) -> AnyView {
        if explanationCaseNames.contains(name) {
            return AnyView(EmptyView())
        }
        return AnyView(
            WorkbenchRowAction(state: state, result: result)
                .frame(width: 320, height: 44, alignment: .trailing))
    }

    /// Each case names the row it is drawn against, because several states only
    /// differ in what the row carries (an App Store listing, a region mismatch).
    /// Sharing one row collapses those into identical pictures.
    static let all: [(String, RowActionState, UpdateResult)] = [
        ("01-awaiting-quit-confirm", .awaitingQuitConfirm("Example"), app),
        ("02-relaunching", .relaunching, app),
        ("03-pending-batch-restart", .pendingBatchRestart, app),
        ("04-just-updated", .justUpdated, app),
        ("05-installing-queued", .installing(.queued), app),
        ("06-installing-downloading", .installing(.downloading(fraction: 0.42)), app),
        ("07-installing-extracting", .installing(.extracting), app),
        ("08-ignored", .ignored, app),
        ("09-version-skipped", .versionSkipped, app),
        ("10-relaunch-to-apply-staged", .relaunchToApplyStaged(to: "1.3.0"), app),
        ("11-restart-to-apply", .restartToApply, app),
        ("12-update-auto-install", .updateAvailable(.autoInstall), app),
        ("13-update-installer", .updateAvailable(.installer(stagedFileName: nil)), app),
        ("14-update-installer-staged", .updateAvailable(.installer(stagedFileName: "Example.pkg")), app),
        ("15-update-toolbox", .updateAvailable(.toolbox), app),
        ("16-update-testflight", .updateAvailable(.testFlight), app),
        ("17-update-self-updater", .updateAvailable(.selfUpdater), app),
        ("18-update-major-upgrade", .updateAvailable(.majorUpgrade), app),
        ("19-update-app-store", .updateAvailable(.appStore(managedHere: false, gate: .none)), storeApp),
        ("20-update-app-store-managed-here", .updateAvailable(.appStore(managedHere: true, gate: .none)), storeApp),
        ("21-update-app-store-region-locked", .updateAvailable(.appStore(managedHere: false, gate: .region)), storeRegionLocked),
        ("22-update-app-store-mac-incompatible", .updateAvailable(.appStore(managedHere: false, gate: .macIncompatible)), storeMacIncompatible),
        ("23-update-detection-only", .updateAvailable(.detectionOnly), app),
        ("24-check-failed", .checkFailed(message: "The request timed out.", rateLimited: false), app),
        ("25-check-failed-rate-limit", .checkFailed(message: "API rate limit exceeded for 1.2.3.4.", rateLimited: true), app),
        ("26-no-source-covers", .noSourceCovers(hint: .none), app),
        ("27-managed-app-store", .managedElsewhere(.appStore), app),
        ("28-managed-toolbox", .managedElsewhere(.toolbox), app),
        ("29-managed-testflight", .managedElsewhere(.testFlight), app),
        ("30-up-to-date", .upToDate(channel: .none), app),
        // `.upToDate` is not one picture: a store-managed or TestFlight app keeps
        // its channel marker so it never reads like something we could update
        // ourselves. Used to need a dedicated MAS/TestFlight-flagged `InstalledApp`
        // fixture to reach these branches at all (the view read `result.app`
        // directly) — now the branch keys off the state's `channel`/`hint`, same
        // plain `app` row as everything else (issue #260).
        ("31-up-to-date-app-store", .upToDate(channel: .appStore), app),
        ("32-up-to-date-testflight", .upToDate(channel: .testFlight), app),
        ("33-no-source-covers-app-store", .noSourceCovers(hint: .appStore), app),
        ("34-no-source-covers-sparkle", .noSourceCovers(hint: .sparkle), app),

        // #265: `DownloadReadout` has three cases and `showsStageLabel` two, but the
        // gallery only ever constructed `PopoverRowAction` with their defaults
        // (`.barAndPercent`, `{ _ in true }`) — so `ringAndPercent`, `ringOnly` and
        // the unlabelled-spinner branch were drawn by nothing. `downloadReadout` and
        // `showsStageLabel` are already `PopoverRowAction` init parameters (measured
        // by the row in production, see `MenuContentView.downloadReadout`); these
        // three cases just supply the non-default values, via
        // `popoverDownloadReadoutOverrides`/`popoverShowsStageLabelOverrides` below,
        // keyed by name so the override sits beside its row instead of reshaping the
        // tuple every other case already uses. The workbench has no
        // such parameter — it always renders full width — so on that surface these
        // three read as ordinary rows; different fractions/stage from every existing
        // case keep them from colliding with 06/07 there without needing an
        // exemption.
        ("35-download-ring-and-percent", .installing(.downloading(fraction: 0.65)), app),
        ("36-download-ring-only", .installing(.downloading(fraction: 0.83)), app),
        // `.verifyingSignature` rather than reusing `.queued`/`.extracting`: those
        // two are already drawn (05, 07) with a label, and reusing one of them here
        // would make this tile's workbench half byte-identical to that case's —
        // an unused `InstallStage` sidesteps the collision instead of asking for an
        // exemption for it.
        ("37-stage-label-hidden", .installing(.verifyingSignature), app),

        // The three explanation popovers sit behind `@State` flags that only a live
        // click can flip — `RowStateGallery` never opens a real popover. Instead,
        // for exactly these three names, the popover surface (see `popoverTile`
        // below) reads `majorUpgradePopover` / `regionHintPopover` /
        // `macCompatHintPopover` directly off a freshly constructed
        // `PopoverRowAction` and draws THAT view — the panel's content, with no
        // `.popover(isPresented:)` involved. Production behavior is unchanged: the
        // flags this bypasses still start `false` on every real row. The state/row
        // pairing is deliberately identical to the case that shows the badge
        // (18, 21, 22) — the badge is what the button that opens this panel looks
        // like; this is what's inside it. The workbench has nothing analogous to
        // draw for "show me the popover's panel", so it renders EmptyView (see
        // `mayBeBlank`) rather than repeating 18/21/22's tile under a new name.
        ("38-major-upgrade-explanation", .updateAvailable(.majorUpgrade), app),
        ("39-region-hint-explanation", .updateAvailable(.appStore(managedHere: false, gate: .region)), storeRegionLocked),
        ("40-mac-compat-hint-explanation", .updateAvailable(.appStore(managedHere: false, gate: .macIncompatible)), storeMacIncompatible),
    ]

    /// Popover-only overrides for the three readout/stage-label cases above, keyed
    /// by name. `PopoverRowAction`'s `downloadReadout` and `showsStageLabel` are
    /// layout knobs the ROW measures in production and hands down (see its doc
    /// comment) — the gallery has no row to measure with, so these three cases set
    /// them explicitly instead of taking the defaults every other case relies on.
    static let popoverDownloadReadoutOverrides: [String: DownloadReadout] = [
        "35-download-ring-and-percent": .ringAndPercent,
        "36-download-ring-only": .ringOnly,
    ]
    static let popoverShowsStageLabelOverrides: [String: (InstallStage) -> Bool] = [
        "37-stage-label-hidden": { _ in false },
    ]

    /// Names whose popover tile is a popover's CONTENT rather than a row — see the
    /// comment on cases 38–40 above. Shared between `popoverTile` (which switches
    /// on it) and `workbenchTile` (which uses it to draw `EmptyView` instead of
    /// repeating an existing tile under a new name).
    static let explanationCaseNames: Set<String> = [
        "38-major-upgrade-explanation",
        "39-region-hint-explanation",
        "40-mac-compat-hint-explanation",
    ]

    /// Tiles that are ALLOWED to draw nothing — keyed by SURFACE and state, not by
    /// state alone. The workbench draws `EmptyView` for a current row; the popover
    /// draws a checkmark. Exempting the name on both surfaces disarms the detector
    /// on the popover's checkmark, so a regression there would report "nothing is
    /// blank". Everything not listed drawing nothing is the bug this gallery exists
    /// to catch.
    static let mayBeBlank: Set<String> = [
        "workbench/30-up-to-date",
        // The workbench has no view for "the popover's explanation panel" — see
        // `workbenchTile` above. Its badge for the same state is already drawn at
        // 18/21/22; these three names exist only to exercise the popover half.
        "workbench/38-major-upgrade-explanation",
        "workbench/39-region-hint-explanation",
        "workbench/40-mac-compat-hint-explanation",
    ]

    /// Pairs of states that legitimately draw the same picture, keyed
    /// `surface/state` — the SAME rule `mayBeBlank` follows, and for the same
    /// reason. Written first with bare state names, which earned each exemption on
    /// one surface and switched the check off on the other for free: two of the
    /// seven below hold on one surface only.
    ///
    /// The App Store gate pair used to be here too (`21-…-region-locked` ==
    /// `22-…-mac-incompatible` on the workbench), justified by what the WORKBENCH
    /// drew — one amber Label for both gates. Issue #260 moved the gate itself
    /// (`AppStoreGate`, carried on the route) out of the views, and the workbench
    /// now draws a distinct Label per gate rather than re-deriving one Label from
    /// `result.remote?.appStore`, so the pair no longer looks alike — removed
    /// rather than carried forward, per the rule below it: an exemption that stops
    /// matching anything is a free pass for future drift, not a thing to keep. The
    /// same issue also added the workbench halves of the managed/up-to-date pairs
    /// below, once the workbench started drawing `.upToDate`'s channel instead of
    /// `EmptyView` — those two pairs now hold on both surfaces rather than one.
    static let mayLookAlike: Set<Set<String>> = [
        // Both an orange bordered "Relaunch"; the help text says which one.
        ["popover/10-relaunch-to-apply-staged", "popover/11-restart-to-apply"],
        ["workbench/10-relaunch-to-apply-staged", "workbench/11-restart-to-apply"],
        // Both a bordered "Update": the pkg route downloads an installer, the App
        // Store route hands off to the store. Same word because the store uses it
        // too; the tooltip is what separates them.
        ["popover/13-update-installer", "popover/19-update-app-store"],
        ["workbench/13-update-installer", "workbench/19-update-app-store"],
        // "Toolbox owns the update" and "Toolbox owns the app" are one button.
        ["popover/15-update-toolbox", "popover/28-managed-toolbox"],
        ["workbench/15-update-toolbox", "workbench/28-managed-toolbox"],
        // Popover only: both are a bordered "Open" — into the app's own updater, or
        // onto its download page. The workbench labels them differently.
        ["popover/17-update-self-updater", "popover/23-update-detection-only"],
        // Popover only: both are an amber triangle opening an explanation popover,
        // and a tile cannot show which explanation appears.
        ["popover/18-update-major-upgrade", "popover/22-update-app-store-mac-incompatible"],
        // Deliberate on both surfaces: a store-managed / TestFlight-managed app
        // that is CURRENT keeps the same marker as one the store/TestFlight
        // manages generally, so a managed row never reads like something we could
        // update ourselves. `RowAction.state` returns the same tile either way —
        // `.managedElsewhere(.appStore)` and `.upToDate(channel: .appStore)` share
        // one branch in both `PopoverRowAction` and `WorkbenchRowAction` now that
        // the workbench actually draws `.upToDate`'s channel instead of `EmptyView`.
        ["popover/27-managed-app-store", "popover/31-up-to-date-app-store"],
        ["workbench/27-managed-app-store", "workbench/31-up-to-date-app-store"],
        ["popover/29-managed-testflight", "popover/32-up-to-date-testflight"],
        ["workbench/29-managed-testflight", "workbench/32-up-to-date-testflight"],
    ]

    /// Tiles whose PICTURE is a harness artifact and must not be read as the real
    /// UI. `ImageRenderer` draws an SF Symbol inside a `.buttonStyle(.borderless)`
    /// button as a yellow "unavailable" placeholder instead of the glyph — verified
    /// with a three-way probe: a bare `Image(systemName:)` renders correctly, the
    /// same image wrapped in a borderless Button does not, and `.popover` has no
    /// bearing on it. These three are the popover's amber/globe badges, and the
    /// workbench draws the same states correctly (it uses `Label`, not a borderless
    /// button), so the pair is still worth comparing for CONTENT — just not for how
    /// the badge itself looks.
    ///
    /// They are still checked for blank and for collisions: the state coverage is
    /// real even when the glyph is not.
    static let notFaithful: Set<String> = [
        "popover/18-update-major-upgrade",
        "popover/21-update-app-store-region-locked",
        "popover/22-update-app-store-mac-incompatible",
        // A DIFFERENT `ImageRenderer` gap, found while adding this case for #265:
        // it also cannot draw a plain native `ProgressView()` — the yellow/red
        // "unavailable" placeholder stands in for the spinner on BOTH surfaces (no
        // `Label`/borderless-button escape hatch here, unlike the three above).
        // The state coverage is still real (no stage label is drawn, which is the
        // branch this case exists to exercise) — only the spinner glyph itself is
        // the harness artifact. This same substitution is visible on several
        // already-committed tiles that predate #265 (e.g. 02/05/06/07's spinners
        // and progress bar); widening this list to cover those is a separate,
        // larger cleanup and out of scope here — flagged instead of silently
        // left off this one new case.
        "popover/37-stage-label-hidden",
        "workbench/37-stage-label-hidden",
    ]

    /// "Nothing was drawn" — every pixel matches the window background painted
    /// behind the view.
    ///
    /// Scans EVERY pixel. A sampled grid was tried first and reported
    /// `24-no-source-covers` as blank: its glyph is a single faint em dash a few
    /// pixels tall, and the grid stepped straight over it. A false "blank" here
    /// would send someone hunting a rendering bug that does not exist, so ordinary
    /// row tiles are small enough (672×120) to just look at all of it — and the
    /// three explanation-content tiles (#265), though bigger, get the same full
    /// scan rather than a size-conditioned shortcut.
    static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
        guard let first = rep.colorAt(x: 0, y: 0) else { return false }
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if abs(c.redComponent - first.redComponent) > 0.01
                    || abs(c.greenComponent - first.greenComponent) > 0.01
                    || abs(c.blueComponent - first.blueComponent) > 0.01 {
                    return false
                }
            }
        }
        return true
    }

    /// `DownloadReadout`'s declaration order IS the algorithm `AppRow.downloadReadout`
    /// runs — widest first, first fit wins (see that property's doc comment). The
    /// gallery tiles added for #265 make the three cases look different, but a diff
    /// in a committed PNG is not an assertion; nothing stopped a future reorder from
    /// landing as an unremarkable-looking diff across three files, still red-handed
    /// only to someone who actually opens them. This is the assertion, independent
    /// of what gets rendered.
    ///
    /// Mutation-tested by hand: swapping `ringAndPercent` and `ringOnly` in
    /// `RowActionViews.swift`'s declaration turns this red (`make gallery` exits 1
    /// with the message below); putting the declaration back turns it green again.
    static func downloadReadoutOrderIsIntact() -> Bool {
        func rank(_ readout: DownloadReadout) -> Int {
            switch readout {
            case .barAndPercent: return 0
            case .ringAndPercent: return 1
            case .ringOnly: return 2
            }
        }
        let ranks = DownloadReadout.allCases.map(rank)
        return ranks == ranks.sorted()
    }
}
