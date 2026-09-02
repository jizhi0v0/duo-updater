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

    /// Same app, but flagged as store-managed / TestFlight / Sparkle-fed. Several
    /// branches key off the ROW rather than the state — `.upToDate` and the source
    /// hint both do — so with one plain fixture five branches were drawn by nothing.
    /// Exactly the failure the App Store fixtures above exist to prevent, one file
    /// over.
    private static let masInstalled = InstalledApp(
        name: "Example", bundleID: "com.example.app",
        shortVersion: "1.2.3", buildVersion: "1230",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        isMASApp: true, sparkleFeedURL: nil)
    private static let sparkleInstalled = InstalledApp(
        name: "Example", bundleID: "com.example.app",
        shortVersion: "1.2.3", buildVersion: "1230",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        isMASApp: false, sparkleFeedURL: URL(string: "https://example.com/appcast.xml"))
    private static let testFlightInstalled = InstalledApp(
        name: "Example", bundleID: "com.example.app",
        shortVersion: "1.2.3", buildVersion: "1230",
        path: URL(fileURLWithPath: "/Applications/Example.app"),
        isMASApp: false, isTestFlightApp: true, sparkleFeedURL: nil)

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
    /// different types; the gallery only needs "draw this state".
    @MainActor
    static let surfaces: [(String, (RowActionState, UpdateResult) -> AnyView)] = [
        ("popover", { AnyView(PopoverRowAction(state: $0, result: $1)) }),
        ("workbench", { AnyView(WorkbenchRowAction(state: $0, result: $1)) }),
    ]

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
        ("19-update-app-store", .updateAvailable(.appStore(managedHere: false)), storeApp),
        ("20-update-app-store-managed-here", .updateAvailable(.appStore(managedHere: true)), storeApp),
        ("21-update-app-store-region-locked", .updateAvailable(.appStore(managedHere: false)), storeRegionLocked),
        ("22-update-app-store-mac-incompatible", .updateAvailable(.appStore(managedHere: false)), storeMacIncompatible),
        ("23-update-detection-only", .updateAvailable(.detectionOnly), app),
        ("24-check-failed", .checkFailed(message: "The request timed out.", rateLimited: false), app),
        ("25-check-failed-rate-limit", .checkFailed(message: "API rate limit exceeded for 1.2.3.4.", rateLimited: true), app),
        ("26-no-source-covers", .noSourceCovers, app),
        ("27-managed-app-store", .managedElsewhere(.appStore), app),
        ("28-managed-toolbox", .managedElsewhere(.toolbox), app),
        ("29-managed-testflight", .managedElsewhere(.testFlight), app),
        ("30-up-to-date", .upToDate, app),
        // `.upToDate` is not one picture: a store-managed or TestFlight app keeps
        // its channel marker so it never reads like something we could update
        // ourselves, and the source hint has three answers of its own. The workbench
        // draws EmptyView for all of them — deliberate, and now visible as such.
        ("31-up-to-date-app-store", .upToDate, result(app: masInstalled)),
        ("32-up-to-date-testflight", .upToDate, result(app: testFlightInstalled)),
        ("33-no-source-covers-app-store", .noSourceCovers, result(app: masInstalled)),
        ("34-no-source-covers-sparkle", .noSourceCovers, result(app: sparkleInstalled)),
    ]

    /// Tiles that are ALLOWED to draw nothing — keyed by SURFACE and state, not by
    /// state alone. The workbench draws `EmptyView` for a current row; the popover
    /// draws a checkmark. Exempting the name on both surfaces disarms the detector
    /// on the popover's checkmark, so a regression there would report "nothing is
    /// blank". Everything not listed drawing nothing is the bug this gallery exists
    /// to catch.
    static let mayBeBlank: Set<String> = [
        "workbench/30-up-to-date",
        "workbench/31-up-to-date-app-store",
        "workbench/32-up-to-date-testflight",
    ]

    /// Pairs of states that legitimately draw the same picture, keyed
    /// `surface/state` — the SAME rule `mayBeBlank` follows, and for the same
    /// reason. Written first with bare state names, which earned each exemption on
    /// one surface and switched the check off on the other for free: four of the
    /// seven below hold on one surface only. The worst was the App Store pair,
    /// justified by what the WORKBENCH draws (one amber Label for both gates) while
    /// silently disarming the popover, where those two must stay a globe badge and
    /// a triangle badge — the whole reason this window is called the richer one.
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
        // Workbench only: it draws a plain "TestFlight" label for both. The popover
        // offers a Button for the update case, so there the two DO differ.
        ["workbench/16-update-testflight", "workbench/29-managed-testflight"],
        // Popover only: both are a bordered "Open" — into the app's own updater, or
        // onto its download page. The workbench labels them differently.
        ["popover/17-update-self-updater", "popover/23-update-detection-only"],
        // Popover only: both are an amber triangle opening an explanation popover,
        // and a tile cannot show which explanation appears.
        ["popover/18-update-major-upgrade", "popover/22-update-app-store-mac-incompatible"],
        // Workbench only: it collapses both App Store gates into one amber Label and
        // points at the popover; the tooltip names which gate it is.
        ["workbench/21-update-app-store-region-locked", "workbench/22-update-app-store-mac-incompatible"],
        // Popover only, and deliberate: a store-managed app that is CURRENT keeps
        // the same marker as one the store manages generally, so a managed row never
        // reads like something we could update ourselves — a bare checkmark looks
        // identical to Sparkle's. The code says so at `.upToDate`'s isMASApp branch.
        ["popover/27-managed-app-store", "popover/31-up-to-date-app-store"],
        ["popover/29-managed-testflight", "popover/32-up-to-date-testflight"],
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
    ]

    /// "Nothing was drawn" — every pixel matches the window background painted
    /// behind the view.
    ///
    /// Scans EVERY pixel. A sampled grid was tried first and reported
    /// `24-no-source-covers` as blank: its glyph is a single faint em dash a few
    /// pixels tall, and the grid stepped straight over it. A false "blank" here
    /// would send someone hunting a rendering bug that does not exist, so the tile
    /// is small enough (672×120) to just look at all of it.
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
}
