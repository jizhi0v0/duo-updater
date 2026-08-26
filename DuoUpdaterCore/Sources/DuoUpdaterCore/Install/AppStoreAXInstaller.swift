#if os(macOS)
import AppKit
import ApplicationServices

/// Updates a Mac App Store app by driving App Store.app's own "Update" button
/// through the Accessibility (AX) API — the *incremental* counterpart to
/// ``MASInstaller`` (which redownloads the full package via the `mas` CLI).
///
/// Why this exists alongside `mas`:
///   • **Delta downloads.** App Store's Update button asks `storedownloadd` for an
///     incremental patch; `mas install --force` redownloads the whole app. For a
///     bandwidth-conscious user this is the cheaper path.
///   • **No `mas` dependency.** This needs no Homebrew/`mas` install — only the
///     App Store app that ships with macOS.
/// The cost is an **Accessibility** TCC grant (the caller guides the user through
/// it with the same PermissionFlow panel used for App Management).
///
/// How it works:
///   1. Make sure App Store is running (launching it in the background first if
///      needed, so the deep link doesn't race a cold launch onto the home page),
///      then `open -g macappstore://apps.apple.com/app/id<trackID>` to navigate to
///      the product page. App Store renders the page without yet coming to the front.
///   2. Find the product page's offer button — a stable `AXIdentifier` of
///      `AppStore.offerButton` (the visible title is localized: Update / Open /
///      Get / …, so we never match on it; we already know an update is due). We
///      bind that button to *this* app structurally before pressing it — see
///      `offerButton(in:appName:viaUpdatesList:)`. Navigation is asynchronous, so
///      until the deep link lands App Store still shows whatever it had before (its
///      restored Discover page, or another app's product page), whose offer buttons
///      are *buy* buttons for apps the user does not own.
///   3. `AXPress` the button *with the app still running* — entirely in the
///      background, never bringing App Store to the front. A backgrounded App Store
///      honors the press (verified 2026-06-05 via a direct probe, and long relied on
///      by the region-locked Updates-list path), so the whole update runs without
///      stealing focus. The delta then downloads in the background while the user keeps
///      working; the button's title reports live progress as "`N% loaded`", parsed into
///      `InstallStage.downloading`.
///   4. Only once the download finishes does App Store raise an `AXSheet` ("Close
///      This App to Update" / Continue · Cancel) — and only because the app is open.
///      We gate that sheet behind the UI's Relaunch tap (`confirmQuit`), then finish the
///      update by **quitting the app ourselves while foregrounding App Store** — we do
///      *not* press the sheet's Continue, because App Store custom-draws this sheet with
///      no accessible affirmative button (`AXDefaultButton` is nil and Continue isn't in
///      the AX tree at all — only Cancel is reachable; verified 2026-06-08). Quitting the
///      app IS the consent the sheet asks for (graceful `terminate()`; see
///      `terminateAndWait`), and foregrounding App Store is required for it to complete
///      the swap — backgrounded, it parks the sheet and never swaps even after the app
///      exits. A sheet that appears *without* a download behind it is a subscription /
///      purchase / terms confirmation, which we never touch — we surface it for manual
///      handling.
public actor AppStoreAXInstaller {

    public init() {}

    public enum AXError: LocalizedError {
        case notTrusted
        case appStoreUnavailable
        case offerButtonNotFound
        case notInUpdatesList
        case cancelled
        case needsManualConfirmation
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .notTrusted:
                return "DuoUpdater needs Accessibility access to drive App Store updates."
            case .appStoreUnavailable:
                return "Couldn’t open the App Store."
            case .offerButtonNotFound:
                return "Couldn’t find the update button on the App Store page."
            case .notInUpdatesList:
                // Region-locked apps have no usable product page (it shows "App Not
                // Available"), so we drive App Store's Updates list instead — which
                // only carries the app once the store has surfaced its update, on its
                // own schedule. Until then there's nothing to press.
                return "The App Store hasn’t listed this update yet. It surfaces region-locked updates on its own schedule — try again once it appears in the App Store’s Updates list."
            case .cancelled:
                return "Update cancelled."
            case .needsManualConfirmation:
                // A subscription / purchase / terms sheet — never auto-confirmed.
                return "This app needs confirmation in the App Store (e.g. a subscription or purchase). Open the App Store and update it there."
            case .timedOut:
                return "Timed out waiting for the App Store."
            }
        }
    }

    /// Whether this process currently holds Accessibility (AX) trust. Cheap, and
    /// the answer changes only when the user toggles the grant, so callers can poll.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask the system to prompt for Accessibility access (adds us to the list with
    /// the deny/allow sheet). Returns the current trust state. The richer guided
    /// flow is the caller's PermissionFlow panel; this is the plain system prompt.
    @discardableResult
    public static func requestTrust() -> Bool {
        // Literal key rather than the `kAXTrustedCheckOptionPrompt` global, which
        // Swift 6 flags as non-concurrency-safe shared mutable state.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Drive an App Store update for the app with the given numeric track id.
    ///
    /// - Parameters:
    ///   - trackID: the App Store numeric id (`AppStoreAvailability.trackID`).
    ///   - onStage: progress callback, same contract as the other installers.
    ///   - confirmQuit: invoked with the running app's name when App Store asks to
    ///     quit it to finish installing. Return `true` to press Continue (the app
    ///     quits and the update lands), `false` to press Cancel (throws `.cancelled`).
    ///     Not called when the app isn't running — then the update installs directly.
    ///   - viaUpdatesList: drive App Store's **Updates list** (`showUpdatesPage`) and
    ///     locate the app's row by name, instead of opening its product page. Required
    ///     for **region-locked** apps: their product page is unreachable under a
    ///     different storefront ("App Not Available"), but an already-installed
    ///     region-locked app still appears in the Updates list and updates normally
    ///     from there. On this path the press registers **without activating** App
    ///     Store (verified on macOS 26), so the whole update runs fully in the
    ///     background. Throws `.notInUpdatesList` when the app isn't in the list yet
    ///     (the store surfaces such updates on its own schedule).
    public func update(
        trackID: Int,
        appPath: URL,
        bundleID: String?,
        appName: String,
        currentShortVersion: String?,
        viaUpdatesList: Bool = false,
        onStage: @Sendable @escaping (InstallStage) -> Void,
        confirmQuit: @Sendable @escaping (String) async -> Bool
    ) async throws {
        guard Self.isTrusted else { throw AXError.notTrusted }

        let runningAtStart = bundleID.map { isRunning($0) } ?? false
        Log.install.info("appstore-ax: start \(appName, privacy: .public) [\(bundleID ?? "?", privacy: .public)] trackID=\(trackID) viaUpdatesList=\(viaUpdatesList) running=\(runningAtStart)")

        onStage(.checking)

        // Bring App Store up *before* the deep link so the navigation doesn't race a
        // cold launch (a freshly-launched App Store drops the deep link on the home
        // page). When we launch it ourselves, give it a moment to finish coming up.
        let (store, didLaunch) = try await ensureAppStoreRunning()
        if didLaunch { try await Task.sleep(for: .seconds(1)) }
        if viaUpdatesList {
            // The product page is "App Not Available" for region-locked apps; the
            // Updates list (`showUpdatesPage` — NOT `updates`, which lands on Discover)
            // carries the row and lets it update. Reliable even on a cold launch. Merely
            // landing here only shows App Store's *cached* update set, so if the row isn't
            // present yet `waitForOfferButton` fires ⌘R to force a server re-fetch and
            // waits for it to surface (see there) before giving up with `.notInUpdatesList`.
            try navigate("macappstore://showUpdatesPage")
        } else {
            try navigateToProductPage(trackID: trackID)
        }

        let axApp = AXUIElementCreateApplication(store.processIdentifier)

        // The deep link above selects the Updates *tab*, which a leftover product page
        // sits on top of — so on its own it can leave the list invisible. Uncover it.
        if viaUpdatesList { await popToUpdatesList(in: axApp) }

        // Everything runs fully in the background — App Store is never brought to the
        // front. Both AX *reads* and the offer-button `AXPress` honor a backgrounded App
        // Store: the Updates-list path has always relied on this (a region-locked update
        // installs silently with no activation), and a direct probe confirmed the
        // *product-page* offer button behaves the same — pressing it launched/installed
        // with App Store never frontmost (2026-06-05). So neither path activates; the
        // update runs without stealing focus or flashing App Store to the foreground.

        guard try await waitForOfferButton(in: axApp, appName: appName, viaUpdatesList: viaUpdatesList, renavigateTrackID: viaUpdatesList ? nil : trackID) != nil else {
            Log.install.error("appstore-ax: \(appName, privacy: .public) offer button not found (viaUpdatesList=\(viaUpdatesList))")
            throw viaUpdatesList ? AXError.notInUpdatesList : AXError.offerButtonNotFound
        }
        Log.install.info("appstore-ax: \(appName, privacy: .public) offer button located")

        // Baseline the on-disk version *before* pressing, so completion is gated on
        // the bundle actually changing (see driveToCompletion) rather than on the
        // localized button title — which, for a fast download, flips back to a
        // non-progress state before storedownloadd has swapped the bundle in. We
        // baseline BOTH the marketing (short) and build versions: an App Store
        // update usually bumps the short version, but a build-only re-release bumps
        // only CFBundleVersion — keying completion on the short version alone would
        // miss that and falsely "time out" on a successful install.
        let baseline = installedVersions(appPath, fallbackShort: currentShortVersion)

        // Press Update *with the app still running*. App Store downloads the delta in
        // the background while the user keeps working — it only raises the "Close this
        // app to update" sheet once the download has finished (verified). We do NOT
        // quit the app up front (that closed it for the whole download); instead we let
        // the download run and gate that end-of-download sheet behind the user's
        // Relaunch tap, pressing Continue ourselves only then (see driveToCompletion).
        // We already know (from detection) an update is due, so press regardless of the
        // localized title — pressing an up-to-date button no-ops. Re-find the button right
        // before pressing: the ref from the wait can go stale if the page re-rendered.
        guard let offer = offerButton(in: axApp, appName: appName, viaUpdatesList: viaUpdatesList) else {
            Log.install.error("appstore-ax: \(appName, privacy: .public) offer button vanished before press")
            throw viaUpdatesList ? AXError.notInUpdatesList : AXError.offerButtonNotFound
        }
        AXUIElementPerformAction(offer, kAXPressAction as CFString)
        Log.install.info("appstore-ax: \(appName, privacy: .public) pressed Update (baseline short=\(baseline.short ?? "?", privacy: .public) build=\(baseline.build ?? "?", privacy: .public))")
        onStage(.downloading(fraction: 0))

        try await driveToCompletion(
            axApp: axApp,
            bundleID: bundleID,
            appName: appName,
            appPath: appPath,
            baseline: baseline,
            viaUpdatesList: viaUpdatesList,
            onStage: onStage,
            confirmQuit: confirmQuit
        )

        // A product-page install leaves App Store's cached "N updates available" count
        // stale: the install lands but the Updates-list count isn't recomputed, so the
        // Dock badge lingers at its pre-update value until App Store's next background
        // check (verified macOS 26 — opening the Updates list just serves the stale
        // cache; only a forced reload re-fetches). The Updates-list path doesn't need
        // this — its row drops live as it installs, decrementing the count. So only the
        // product-page path nudges the badge. Best-effort: a completed install must
        // never fail over a cosmetic badge, so refreshUpdatesBadge swallows everything.
        if !viaUpdatesList {
            // Fire-and-forget: this only nudges App Store's cosmetic Dock badge and
            // sleeps ~1s doing it. Awaiting it would delay the caller's relaunch of the
            // app the user is waiting to see return, so detach it — the badge self-heals
            // on Apple's next check regardless.
            let pid = store.processIdentifier
            Task { await self.refreshUpdatesBadge(pid: pid) }
        }
    }

    /// Force App Store to recompute its "available updates" count (and thus the Dock
    /// badge) after a product-page install, by navigating to the Updates list and
    /// firing its Reload command — the same ⌘R that, by hand, drops a stale badge that
    /// no amount of reopening App Store / killing Dock clears. Entirely best-effort and
    /// silent: it runs backgrounded (`open -g` + a menu AXPress that needs no
    /// activation), and any failure just leaves the badge to self-heal on Apple's next
    /// check — exactly the prior behavior.
    private func refreshUpdatesBadge(pid: pid_t) async {
        try? navigate("macappstore://showUpdatesPage")
        // Let the Updates view load before reloading it — reloading reissues the
        // server-side update check, which is what recomputes the count.
        try? await Task.sleep(for: .seconds(1))
        reloadUpdatesPage(in: AXUIElementCreateApplication(pid))
    }

    /// Pop any product page covering the Updates list, one level per press.
    ///
    /// App Store's product page is a detail view pushed onto the *sidebar tab's*
    /// navigation stack, not a destination of its own. While one is open, neither
    /// `macappstore://showUpdatesPage` nor pressing the sidebar's own
    /// `AppStore.tabBar.updates` changes what is displayed — both only select a tab that
    /// is already selected, and the tab press even reports success while the product page
    /// stays put (observed 3/3, macOS 26.6). The list's own back button is the only thing
    /// that reveals it, so press it until it is gone.
    ///
    /// This matters because a product page is exactly what the *other* route leaves
    /// behind: without popping, the Updates path's only nudge is ⌘R, which reloads
    /// whatever is on top — the product page — so the row never appeared and the wait
    /// ended in `.notInUpdatesList` with the list one press away.
    ///
    /// Bounded, and a no-op (no sleeping) when there is nothing to pop.
    private func popToUpdatesList(in axApp: AXUIElement) async {
        for _ in 0..<6 {
            var found: [AXUIElement] = []
            collect(axApp, id: "AppStore.productPage.backButton", into: &found)
            guard let back = found.first else { return }
            AXUIElementPerformAction(back, kAXPressAction as CFString)
            try? await Task.sleep(for: .milliseconds(300))  // let the pop land
        }
    }

    /// Fire App Store's "Reload Page" (⌘R) on whatever page is showing. On the Updates
    /// list this **reissues the server-side update check** — the only way to make App
    /// Store re-fetch rather than serve its cached "available updates" snapshot. Silent:
    /// an `AXPress` on the menu item performs it without opening the menu, and needs no
    /// activation. A no-op if the item can't be found / is momentarily disabled (callers
    /// that care just retry on their next poll).
    private func reloadUpdatesPage(in axApp: AXUIElement) {
        if let reload = reloadPageMenuItem(in: axApp) {
            AXUIElementPerformAction(reload, kAXPressAction as CFString)
        }
    }

    /// App Store's "Store → Reload Page" menu item, located by its ⌘R key equivalent
    /// (cmdChar "r", Command-only) rather than its localized title so it survives a
    /// non-English App Store. AXPress on a menu item performs it without opening the
    /// menu visually, keeping the refresh silent.
    private func reloadPageMenuItem(in axApp: AXUIElement) -> AXUIElement? {
        guard let menuBar = attribute(axApp, kAXMenuBarAttribute as String) else { return nil }
        return findCommandMenuItem(menuBar, cmdChar: "r")
    }

    private func findCommandMenuItem(_ el: AXUIElement, cmdChar: String, depth: Int = 0) -> AXUIElement? {
        if depth > 8 { return nil }
        if role(el) == "AXMenuItem",
           string(el, "AXMenuItemCmdChar")?.lowercased() == cmdChar,
           intAttr(el, "AXMenuItemCmdModifiers") == 0 {  // 0 == Command only
            return el
        }
        for c in children(el) {
            if let hit = findCommandMenuItem(c, cmdChar: cmdChar, depth: depth + 1) { return hit }
        }
        return nil
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - Activation

    /// App Store, launched in the background if it isn't already running. Returns
    /// whether we launched it (the caller lets a fresh launch settle before navigating).
    private func ensureAppStoreRunning() async throws -> (NSRunningApplication, didLaunch: Bool) {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.AppStore").first {
            return (app, false)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-b", "com.apple.AppStore"]  // -g background, -b by bundle id
        try p.run()
        p.waitUntilExit()
        return (try await waitForAppStore(), true)
    }

    /// The bundle's marketing (short) and build versions read straight from disk,
    /// used to detect when storedownloadd has finished swapping the new build in.
    /// `fallbackShort` (the caller's known current version) is used only if the
    /// Info.plist can't be read at that instant.
    private func installedVersions(_ appPath: URL, fallbackShort: String? = nil) -> (short: String?, build: String?) {
        let plist = appPath.appendingPathComponent("Contents/Info.plist")
        let dict = NSDictionary(contentsOf: plist)
        let short = (dict?["CFBundleShortVersionString"] as? String) ?? fallbackShort
        let build = dict?["CFBundleVersion"] as? String
        return (short, build)
    }

    /// Completion = a readable on-disk version that differs from `baseline` for
    /// EITHER the short or build key. A `nil` baseline value can't trigger
    /// completion, so a transiently unreadable Info.plist at baseline time can't be
    /// misread as "updated" the instant it becomes readable again.
    private func versionChanged(from baseline: (short: String?, build: String?), appPath: URL) -> Bool {
        let now = installedVersions(appPath)
        if let b = baseline.short, let n = now.short, n != b { return true }
        if let b = baseline.build, let n = now.build, n != b { return true }
        return false
    }

    // MARK: - Navigation

    private func navigateToProductPage(trackID: Int) throws {
        try navigate("macappstore://apps.apple.com/app/id\(trackID)")
    }

    /// `open -g <url>` — navigate App Store in the background, never stealing focus.
    private func navigate(_ urlString: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", urlString]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AXError.appStoreUnavailable }
    }

    private func waitForAppStore() async throws -> NSRunningApplication {
        for _ in 0..<50 {  // ~10s
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.AppStore").first {
                return app
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw AXError.appStoreUnavailable
    }

    /// The page (product page, or the Updates list) may take a moment to render after
    /// navigation; poll until the app's offer button appears (or give up). The poll is on
    /// a short (150ms) interval so we react promptly once the target lands, and we re-issue
    /// the page's refresh periodically while waiting so a slow load / stale cache heals
    /// instead of failing closed:
    ///   • **Updates list**: fire ⌘R (`reloadUpdatesPage`) — it reissues a *server-side*
    ///     update check, the only way to make App Store re-fetch rather than serve its
    ///     cached "available updates" snapshot. Because that's a network round-trip, this
    ///     path also waits noticeably longer than the product page. (Without the reload, a
    ///     region-locked update that App Store knows about but hasn't pulled into the local
    ///     list would be missed, throwing `.notInUpdatesList` prematurely.)
    ///   • **Product page** (`renavigateTrackID`): re-issue the deep link — a cold-launched
    ///     App Store can drop the first one onto its restored Discover page; resending it
    ///     once the app is fully up lands it on the product page.
    /// The refresh is skipped entirely once the target is present (we return above), so a
    /// cache that already carries the row takes the fast path with no reload.
    private func waitForOfferButton(in axApp: AXUIElement, appName: String, viaUpdatesList: Bool, renavigateTrackID: Int? = nil) async throws -> AXUIElement? {
        let deadline = viaUpdatesList ? 150 : 80   // ~22s (server re-fetch) vs ~12s at 150ms/poll
        for i in 0..<deadline {
            if let offer = offerButton(in: axApp, appName: appName, viaUpdatesList: viaUpdatesList) { return offer }
            // An early nudge once the page has settled (~0.6s), then every ~2.4s.
            if i == 4 || (i > 0 && i % 16 == 0) {
                if viaUpdatesList {
                    // A product page opened while we were waiting would hide the list,
                    // and ⌘R would then just reload *it*. Uncover the list first.
                    await popToUpdatesList(in: axApp)
                    reloadUpdatesPage(in: axApp)
                } else if let trackID = renavigateTrackID {
                    try? navigateToProductPage(trackID: trackID)
                }
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        return nil
    }

    // MARK: - Progress / completion

    /// After pressing Update (with the app still running), poll until the install
    /// lands — detected by the on-disk bundle version changing from `baseline`, the
    /// authoritative, language-independent signal.
    ///
    /// Sheet handling is the delicate part. App Store raises the "Close this app to
    /// update" sheet only *after* the download finishes and only because the app is
    /// open; a subscription / purchase / terms sheet, by contrast, appears *before*
    /// any download (you can't download a paid update without confirming the charge
    /// first). We use that ordering to tell them apart: a sheet that appears once we've
    /// seen download progress, with the app still running, is the close-to-update one —
    /// we gate it behind the user's Relaunch tap (`confirmQuit`), then press its
    /// Continue. Any other sheet (no download behind it, or the app already gone) is a
    /// confirmation we must never auto-press, surfaced as `.needsManualConfirmation`.
    private func driveToCompletion(
        axApp: AXUIElement,
        bundleID: String?,
        appName: String,
        appPath: URL,
        baseline: (short: String?, build: String?),
        viaUpdatesList: Bool,
        onStage: @Sendable @escaping (InstallStage) -> Void,
        confirmQuit: @Sendable @escaping (String) async -> Bool
    ) async throws {
        // Every press here — the quit sheet's Continue/Cancel and the idle re-press —
        // honors a backgrounded App Store, so nothing activates (see `update`). App Store
        // is never brought to the front for the whole install.
        var sheetTicks = 0
        var sawProgress = false   // the download actually started (vs. an immediate sheet)
        var continued = false     // we pressed Continue; the app is quitting + swapping
        var idleTicks = 0         // consecutive polls with no progress and no sheet
        var repressed = false     // we re-pressed Update once after an idle stretch
        var postContinueTicks = 0 // polls since we pressed Continue (to flag a no-op press)

        // ~6 min hard cap of *polling* — the suspension on `confirmQuit` below doesn't
        // burn iterations, so waiting on the user's Relaunch tap never times us out.
        for _ in 0..<900 {
            // 1. Completion: the bundle on disk has been swapped for the new build.
            // Covers both the app-not-running case (installs directly, no sheet) and
            // the post-Continue swap. Keyed on short OR build version changing.
            if versionChanged(from: baseline, appPath: appPath) {
                Log.install.info("appstore-ax: \(appName, privacy: .public) install complete — bundle version changed on disk")
                onStage(.done)
                return
            }

            // After Continue, cap the wait on App Store's swap. The swap normally lands
            // in well under a minute (WeChat ~24s), so if the version hasn't changed
            // ~90s after Continue the swap silently failed (e.g. the app couldn't be
            // quit) — bail rather than spin the full 6-min cap, which would freeze the
            // background scheduler (it defers every tick while an install is in flight).
            if continued {
                postContinueTicks += 1
                if postContinueTicks >= 225 {  // ~90s at 400ms/poll
                    Log.install.error("appstore-ax: \(appName, privacy: .public) timed out — no swap ~90s after Continue (the swap likely never started; app still running=\(bundleID.map { isRunning($0) } ?? false))")
                    throw AXError.timedOut
                }
            }

            // 2. Sheet handling.
            let sheetPresent = quitSheet(in: axApp) != nil
            if sheetPresent {
                if continued {
                    // We've quit the app + foregrounded App Store; the swap is in flight.
                    // Ignore the lingering sheet and wait for the on-disk version to change.
                    // A sheet still up well after we quit usually means the app hasn't
                    // actually exited yet (e.g. it raised a save prompt that our graceful
                    // terminate() won't force past) — flag it once so a stuck install is
                    // diagnosable.
                    if postContinueTicks == 10 {  // ~4s after we quit + foregrounded
                        Log.install.error("appstore-ax: \(appName, privacy: .public) sheet still present ~4s after quit+foreground (app still running=\(bundleID.map { isRunning($0) } ?? false))")
                    }
                } else if sawProgress, let bundleID, isRunning(bundleID) {
                    // Download finished, app still open → App Store's "Close this app to
                    // update" sheet. Gate it behind the user's Relaunch tap, then finish.
                    //
                    // We do NOT press the sheet's affirmative ("Continue" / "Quit & Update")
                    // button: App Store custom-draws this sheet with NO accessible default
                    // button — `AXDefaultButton` is nil and the affirmative button isn't in
                    // the AX tree at all (only "Cancel" is reachable; verified for Spark
                    // 2026-06-08). Every prior "pressed Continue" was a silent no-op. What the
                    // sheet actually asks for is the app to quit, so we deliver that ourselves
                    // (graceful terminate — quitting the app IS the consent the user just gave
                    // via Relaunch; we never force-kill unsaved work).
                    //
                    // Crucially we foreground App Store first: a *backgrounded* App Store parks
                    // this sheet and never completes the swap even after the app exits (Spark,
                    // backgrounded + clean quit: no swap for 94s; same app foregrounded:
                    // swapped — 2026-06-08). This is the only point we steal focus — the whole
                    // download ran in the background; the user just tapped Relaunch and expects
                    // the app to cycle.
                    Log.install.info("appstore-ax: \(appName, privacy: .public) close-to-update sheet shown — awaiting user Relaunch/Cancel")
                    guard await confirmQuit(appName) else {
                        Log.install.info("appstore-ax: \(appName, privacy: .public) user declined — pressing Cancel")
                        pressCancel(in: axApp, appName: appName)
                        throw AXError.cancelled
                    }
                    onStage(.installing)  // "Relaunching" — quit the app, App Store swaps
                    activateAppStore()
                    await terminateAndWait(bundleID: bundleID, appName: appName)
                    continued = true
                    sheetTicks = 0
                } else {
                    // A sheet with no download behind it (or the app already gone) is a
                    // subscription / purchase / terms confirmation. But a *fast* delta can
                    // raise the close-to-update sheet within ~60ms of the press — before the
                    // offer button's title flips to a loading/progress state — so `sawProgress`
                    // is still false for the first poll or two even on a normal update (Spark:
                    // sheet at +60ms, progress at +420ms). Give sawProgress time to win the
                    // race before concluding "subscription": a genuine purchase sheet never has
                    // a download behind it, so it stays past this grace and still bails.
                    sheetTicks += 1
                    if sheetTicks == 1 {
                        Log.install.info("appstore-ax: \(appName, privacy: .public) sheet before any download (sawProgress=\(sawProgress), running=\(bundleID.map { isRunning($0) } ?? false)) — waiting to see if a fast delta's progress lands")
                    }
                    if sheetTicks >= 8 {  // ~3.2s — well past the ~0.5s a real download takes to report progress
                        Log.install.error("appstore-ax: \(appName, privacy: .public) needs manual confirmation — no download after ~3s, bailing without pressing")
                        throw AXError.needsManualConfirmation
                    }
                }
            } else {
                sheetTicks = 0
            }

            // 3. Surface download progress from the offer button title (display only).
            // Once we've pressed Continue the title is meaningless, so stop reading it.
            if !continued, let offer = offerButton(in: axApp, appName: appName, viaUpdatesList: viaUpdatesList), let title = title(offer) {
                if let fraction = Self.progressFraction(title) {
                    if !sawProgress { Log.install.info("appstore-ax: \(appName, privacy: .public) download started") }
                    sawProgress = true
                    onStage(.downloading(fraction: fraction))
                } else if Self.isLoadingTitle(title) {
                    if !sawProgress { Log.install.info("appstore-ax: \(appName, privacy: .public) download starting (loading)") }
                    sawProgress = true
                    onStage(.downloading(fraction: 0))
                }
            }

            // 4. Fail-fast: if the press never took (no progress, no sheet), don't spin
            // the full 6-min cap holding the shared actor. After ~12s idle press once
            // more; if still nothing ~12s later, give up so the next update isn't blocked
            // behind a dead one.
            if continued || sawProgress || sheetPresent {
                idleTicks = 0
            } else {
                idleTicks += 1
                if idleTicks == 30 && !repressed {
                    Log.install.info("appstore-ax: \(appName, privacy: .public) no progress/sheet after ~12s — re-pressing Update once")
                    if let offer = offerButton(in: axApp, appName: appName, viaUpdatesList: viaUpdatesList) {
                        AXUIElementPerformAction(offer, kAXPressAction as CFString)
                    }
                    repressed = true
                } else if idleTicks >= 60 {
                    Log.install.error("appstore-ax: \(appName, privacy: .public) timed out — no progress/sheet ~24s after press (the press never took)")
                    throw AXError.timedOut
                }
            }

            try await Task.sleep(for: .milliseconds(400))
        }
        Log.install.error("appstore-ax: \(appName, privacy: .public) timed out — 6-min poll cap reached (continued=\(continued) sawProgress=\(sawProgress))")
        throw AXError.timedOut
    }

    /// Bring App Store to the front. Used only at the final swap step (after the user
    /// taps Relaunch): a *backgrounded* App Store parks the close-to-update sheet and
    /// never completes the swap even after the app exits, so we foreground it to let the
    /// swap fire (Spark, backgrounded + clean quit: no swap for 94s; foregrounded:
    /// swapped — verified 2026-06-08). The download itself ran fully backgrounded; this
    /// is the only point the installer steals focus.
    private func activateAppStore() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.AppStore")
            .first?
            .activate()
    }

    /// Press the close-to-update sheet's Cancel button on user decline. App Store's sheet
    /// exposes no `AXCancelButton` attribute (it's nil), but its one reachable `AXButton`
    /// IS Cancel — the affirmative button isn't in the AX tree at all (verified Spark
    /// 2026-06-08) — so press that. Best-effort: if we can't find it, the sheet just
    /// lingers for the user to dismiss in App Store.
    private func pressCancel(in axApp: AXUIElement, appName: String) {
        guard let sheet = quitSheet(in: axApp) else {
            Log.install.error("appstore-ax: \(appName, privacy: .public) sheet gone at Cancel time — skipped")
            return
        }
        if let cancel = attribute(sheet, "AXCancelButton") {
            AXUIElementPerformAction(cancel, kAXPressAction as CFString)
            return
        }
        var buttons: [AXUIElement] = []
        collectButtons(sheet, into: &buttons)
        if let cancel = buttons.first {  // the lone reachable button is Cancel
            AXUIElementPerformAction(cancel, kAXPressAction as CFString)
        } else {
            Log.install.error("appstore-ax: \(appName, privacy: .public) no Cancel button reachable — sheet left for manual dismissal")
        }
    }

    /// Collect all `AXButton` descendants of an element (used to reach the sheet's lone
    /// Cancel button, which App Store doesn't expose via the standard `AXCancelButton`).
    private func collectButtons(_ el: AXUIElement, into acc: inout [AXUIElement], depth: Int = 0) {
        if depth > 20 { return }
        if role(el) == "AXButton" { acc.append(el) }
        for c in children(el) { collectButtons(c, into: &acc, depth: depth + 1) }
    }

    /// Quit every running instance of the app *ourselves* (graceful `terminate()`),
    /// then wait up to ~12s for it to actually exit. Called after the user confirms the
    /// "Close this app to update" sheet: a backgrounded App Store presses Continue but
    /// doesn't reliably bring the app down to complete the swap, so we deliver the quit
    /// it's waiting for. Graceful only — if the app puts up a save prompt and won't
    /// exit, we leave it (the install then times out) rather than force-killing unsaved
    /// work. App Store, seeing the app gone, swaps the new build in on its own.
    private func terminateAndWait(bundleID: String, appName: String) async {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
        for _ in 0..<60 {  // ~12s at 200ms
            if !isRunning(bundleID) {
                Log.install.info("appstore-ax: \(appName, privacy: .public) quit — App Store can now swap in the update")
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        Log.install.error("appstore-ax: \(appName, privacy: .public) won't quit within 12s (likely a save prompt) — leaving it; install may time out")
    }

    /// Parse a fraction (0…1) out of an offer-button title like "80% loaded" or
    /// "0.1% loaded". Digits and "%" are not localized; the word after them may be.
    static func progressFraction(_ title: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%"#),
              let m = re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: title),
              let value = Double(title[r]) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    /// A transient pre-progress state ("Loading", "Opening…") shown right after the
    /// press, before the percentage appears. English-only on purpose — it's just a
    /// nicety; a missed match only delays the first non-zero progress tick.
    static func isLoadingTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("loading") || lower.contains("opening") || lower.contains("waiting")
    }

    // MARK: - AX lookups

    /// The offer button to press, by path:
    ///   • **Product page** (default): several `AppStore.offerButton`s can exist, and
    ///     the ones that are not ours belong to apps the user does not own — pressing
    ///     one *buys* something. So we bind the button to this app with two structural,
    ///     language-independent checks (see `ShelfCell`): the page's **hero lockup**
    ///     must name this app, and the button must not sit in another app's card.
    ///     Only if exactly one button survives do we return it; otherwise nil, and the
    ///     caller keeps waiting (and re-navigating) rather than pressing anything.
    ///   • **Updates list** (`viaUpdatesList`): one row per app, each with its own
    ///     offer button. We pick the row whose nearby text carries `appName`, matching
    ///     by name rather than position or the localized button title (which reads
    ///     "Update"/"更新"/… and is unreliable). Returns nil when no row matches — the
    ///     app isn't in the list yet.
    private func offerButton(in axApp: AXUIElement, appName: String, viaUpdatesList: Bool) -> AXUIElement? {
        var found: [AXUIElement] = []
        collect(axApp, id: "AppStore.offerButton", into: &found)
        guard viaUpdatesList else {
            // 1. Has the deep link actually landed on THIS app's page? Navigation is
            //    asynchronous, so until it has, App Store is still showing its restored
            //    Discover page or another app's product page — both full of buy buttons.
            // 2. Drop every button that belongs to some other app's card, and press only
            //    if that leaves exactly one. Position is not a discriminator: the topmost
            //    button belongs to whichever page rendered highest, not to us.
            let ours = found.filter { !isInForeignCard($0) }
            guard Self.shouldPress(heroOwnsPage: heroOwns(appName, in: axApp),
                                   ownButtonCount: ours.count) else { return nil }
            return ours[0]
        }
        // An inline loop (not `compactMap`) so `axApp` never crosses into a closure:
        // Swift 6.2's region-based isolation rejects passing this non-Sendable
        // AXUIElement into the actor-isolated map closure, even though the work is
        // fully synchronous and on-actor. The loop body stays in this isolation
        // domain, so there's nothing to "send".
        var rows: [(AXUIElement, [String])] = []
        for btn in found {
            rows.append((btn, rowTexts(in: axApp, for: btn, among: found)))
        }
        // Prefer an exact app-name match (the row's title text); fall back to a
        // contains-match for apps whose Updates-list label carries extra decoration.
        if let exact = rows.first(where: { $0.1.contains(appName) })?.0 { return exact }
        return rows.first(where: { row in
            row.1.contains { $0.localizedCaseInsensitiveContains(appName) }
        })?.0
    }

    /// How one of App Store's `AppStore.shelfItem.*` cells relates to the app we're
    /// updating. Every app that appears anywhere in App Store's UI is wrapped in such a
    /// cell, and the *subtype* says whose app it is (observed macOS 26.6, 2026-08-26):
    ///
    ///   • `…ProductLockupCollectionViewCell` — the product page's own **hero lockup**:
    ///     icon, name, subtitle, and the offer button we actually want.
    ///   • every other subtype (`…SmallLockupCollectionViewCell`, …) — some **other**
    ///     app: Discover's featured rows, "Also Included In" subscription bundles,
    ///     "More by this developer".
    ///
    /// Both are structural and language-independent, unlike the button's own title.
    /// Kept as a pure function of the identifier so it is directly testable.
    enum ShelfCell: Equatable {
        case notACell
        case hero
        case foreign

        init(identifier: String?) {
            guard let identifier, identifier.hasPrefix("AppStore.shelfItem") else {
                self = .notACell
                return
            }
            self = identifier.contains("ProductLockup") ? .hero : .foreign
        }
    }

    /// The product-page press/wait decision, factored out of the AX traversal so it can
    /// be asserted without a live App Store.
    ///
    /// Both conditions are required and the rule is deliberately fail-closed — returning
    /// `false` only costs another 150 ms poll (and a re-issued deep link), while a wrong
    /// `true` spends the user's money. `ownButtonCount != 1` is a real state, not
    /// paranoia: mid-navigation both the old and the new page are briefly in the AX tree
    /// at once (observed: 8 offer buttons in one poll).
    static func shouldPress(heroOwnsPage: Bool, ownButtonCount: Int) -> Bool {
        heroOwnsPage && ownButtonCount == 1
    }

    /// Whether the page's own hero lockup names `appName` — i.e. App Store really has
    /// landed on THIS app's product page.
    ///
    /// This replaced a check that asked whether the name appeared as text *anywhere*
    /// under App Store's element. That guard was permanently true for exactly the apps
    /// we update: the Apple menu's **Recent Items** submenu hangs off every app's
    /// `AXMenuBar` and lists recently used applications, so
    /// `AXMenuBar > AXMenuBarItem:Apple > … > AXMenuItem:Microsoft Word` satisfied it no
    /// matter which page was showing. The topmost offer button was then pressed on
    /// whatever App Store still had on screen — on a restored Discover page a featured
    /// app's **buy** button (observed `$49.99`), on another app's product page that
    /// app's. Reproduced 5/5 on macOS 26.6, 2026-08-26.
    ///
    /// Restricting the search to hero lockups fixes that at the root: menu bars contain
    /// no shelf cells, and every *other* app named on a page sits in a foreign cell we
    /// never descend into.
    private func heroOwns(_ appName: String, in axApp: AXUIElement) -> Bool {
        var heroes: [AXUIElement] = []
        collectHeroCells(axApp, into: &heroes)
        for hero in heroes where subtreeMentions(appName, hero) { return true }
        return false
    }

    /// Collect the page's hero lockup cells, never descending into any shelf cell (so a
    /// nested card can't be mistaken for the page's own header).
    private func collectHeroCells(_ el: AXUIElement, into acc: inout [AXUIElement], depth: Int = 0) {
        if depth > 45 { return }
        switch ShelfCell(identifier: string(el, "AXIdentifier")) {
        case .hero:    acc.append(el); return
        case .foreign: return
        case .notACell: break
        }
        for c in children(el) { collectHeroCells(c, into: &acc, depth: depth + 1) }
    }

    /// Whether `appName` appears as text in this subtree. `AXValue` is checked first and
    /// is the one that matters: these pages are web-rendered, so a static text's string
    /// lives in `AXValue`, not `AXTitle`.
    private func subtreeMentions(_ appName: String, _ el: AXUIElement, depth: Int = 0) -> Bool {
        if depth > 20 { return false }
        for attr in ["AXValue", kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
            if let t = string(el, attr), t.localizedCaseInsensitiveContains(appName) { return true }
        }
        for c in children(el) {
            if subtreeMentions(appName, c, depth: depth + 1) { return true }
        }
        return false
    }

    /// Whether this offer button sits inside another app's card. The product page's own
    /// header button is either parentless (observed) or inside the hero lockup; either
    /// way it is never inside a foreign cell.
    private func isInForeignCard(_ btn: AXUIElement) -> Bool {
        var cur: AXUIElement? = btn
        for _ in 0..<6 {
            guard let c = cur else { return false }
            if ShelfCell(identifier: string(c, "AXIdentifier")) == .foreign { return true }
            cur = attribute(c, kAXParentAttribute as String)
        }
        return false
    }

    /// Which offer button a row label belongs to: the nearest one to its **right**.
    ///
    /// The Updates list is a two-column grid, so one horizontal band holds two apps.
    /// Each cell lays out as `icon · name · notes … [button]`, so a label always sits
    /// left of its own button and right of the previous column's — which makes
    /// "nearest button to the right" the ownership rule, with no column width or gap
    /// constant to drift when the window is resized.
    ///
    /// Pure and frame-only so the geometry is testable without a live App Store.
    static func owningButton(ofLabelAt label: CGRect, among buttons: [CGRect]) -> CGRect? {
        buttons.filter { $0.minX >= label.maxX }.min { $0.minX < $1.minX }
    }

    /// Static-text strings belonging to this offer button's cell — used to tell which
    /// app an Updates-list button updates (the name renders as a sibling `AXStaticText`,
    /// never on the button itself).
    ///
    /// Two separate bugs used to make this return the wrong thing on macOS 26.6:
    ///   • it read only `AXTitle`/`AXDescription`, but the page is web-rendered and a
    ///     static text's string lives in **`AXValue`**. The title-only read returned
    ///     just the sidebar's own labels (`["Arcade", "Create"]`) and never an app name,
    ///     so no row ever matched and every region-locked update failed with
    ///     `.notInUpdatesList` — "the App Store hasn't listed this update yet" — while
    ///     the row sat right there on screen.
    ///   • it took every text within ±45 px of the button's midY, which in a two-column
    ///     grid is both apps: "Microsoft Excel" (x=341) and "TestFlight" (x=885) share
    ///     the band of the buttons at x=723 and x=1267, so both buttons collected both
    ///     names and the first one answered for every app.
    private func rowTexts(in axApp: AXUIElement, for button: AXUIElement,
                          among buttons: [AXUIElement], tolerance: CGFloat = 45) -> [String] {
        guard let mine = frame(button) else { return [] }
        var labels: [(CGRect, String)] = []
        collectRowTexts(axApp, lo: mine.midY - tolerance, hi: mine.midY + tolerance, into: &labels)
        // Only the buttons sharing this band can own a label in it.
        var band: [CGRect] = []
        for b in buttons {
            if let f = frame(b), abs(f.midY - mine.midY) <= tolerance { band.append(f) }
        }
        return labels.compactMap { Self.owningButton(ofLabelAt: $0.0, among: band) == mine ? $0.1 : nil }
    }

    private func collectRowTexts(_ el: AXUIElement, lo: CGFloat, hi: CGFloat,
                                 into acc: inout [(CGRect, String)], depth: Int = 0) {
        if depth > 60 { return }
        if role(el) == "AXStaticText", let f = frame(el), f.midY >= lo, f.midY <= hi,
           let t = string(el, "AXValue") ?? title(el) {
            acc.append((f, t))
        }
        for c in children(el) { collectRowTexts(c, lo: lo, hi: hi, into: &acc, depth: depth + 1) }
    }

    /// The "Close This App to Update" alert, if present: it surfaces as an `AXSheet`
    /// that is also the app's focused window, or hangs off a window's `AXSheets`.
    private func quitSheet(in axApp: AXUIElement) -> AXUIElement? {
        if let fw = attribute(axApp, "AXFocusedWindow"), role(fw) == "AXSheet" { return fw }
        var winRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winRef)
        for w in (winRef as? [AXUIElement]) ?? [] {
            var sv: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, "AXSheets" as CFString, &sv) == .success,
               let sheet = (sv as? [AXUIElement])?.first {
                return sheet
            }
        }
        return nil
    }

    // MARK: - AX primitives

    private func collect(_ el: AXUIElement, id: String, into acc: inout [AXUIElement], depth: Int = 0) {
        if depth > 45 { return }
        if string(el, "AXIdentifier") == id { acc.append(el) }
        for c in children(el) { collect(c, id: id, into: &acc, depth: depth + 1) }
    }

    private func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private func attribute(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return (v as! AXUIElement?)
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func intAttr(_ el: AXUIElement, _ attr: String) -> Int? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return (v as? NSNumber)?.intValue
    }

    private func role(_ el: AXUIElement) -> String { string(el, kAXRoleAttribute as String) ?? "" }

    private func title(_ el: AXUIElement) -> String? {
        string(el, kAXTitleAttribute as String) ?? string(el, kAXDescriptionAttribute as String)
    }

    private func frame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }
}
#endif
