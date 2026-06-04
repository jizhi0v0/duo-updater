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
///      Get / …, so we never match on it; we already know an update is due).
///   3. Briefly bring App Store to the front and `AXPress` the button *with the app
///      still running*, then hand focus straight back to whoever had it. The
///      momentary activation is required: a backgrounded App Store renders the page
///      but silently swallows the press, so the download never starts (verified).
///      The delta then downloads in the background while the user keeps working; the
///      button's title reports live progress as "`N% loaded`", parsed into
///      `InstallStage.downloading`.
///   4. Only once the download finishes does App Store raise an `AXSheet` ("Close
///      This App to Update" / Continue · Cancel) — and only because the app is open.
///      We gate that sheet behind the UI's Relaunch tap (`confirmQuit`), then press
///      its Continue ourselves (the sheet's `AXDefaultButton`, language-independent;
///      the buttons' own identifiers are unstable `_NS:` values). A sheet that
///      appears *without* a download behind it is a subscription / purchase / terms
///      confirmation, which we never press — we surface it for manual handling.
public actor AppStoreAXInstaller {

    public init() {}

    public enum AXError: LocalizedError {
        case notTrusted
        case appStoreUnavailable
        case offerButtonNotFound
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
    public func update(
        trackID: Int,
        appPath: URL,
        bundleID: String?,
        appName: String,
        currentShortVersion: String?,
        onStage: @Sendable @escaping (InstallStage) -> Void,
        confirmQuit: @Sendable @escaping (String) async -> Bool
    ) async throws {
        guard Self.isTrusted else { throw AXError.notTrusted }

        onStage(.checking)

        // Bring App Store up *before* the deep link so the navigation doesn't race a
        // cold launch (a freshly-launched App Store drops the deep link on the home
        // page). When we launch it ourselves, give it a moment to finish coming up.
        let (store, didLaunch) = try await ensureAppStoreRunning()
        if didLaunch { try await Task.sleep(for: .seconds(1)) }
        try navigateToProductPage(trackID: trackID)

        let axApp = AXUIElementCreateApplication(store.processIdentifier)

        // The AXPress only registers when App Store is the *active* app: a backgrounded
        // App Store renders the page but silently swallows the press, so the download
        // never starts (verified — every `open -g`/never-activated attempt failed,
        // while a foreground press drove the whole flow). Activate just long enough to
        // press, remembering who was frontmost so we can hand focus straight back.
        let priorPID = await currentFrontmostPID()
        await activate(store)
        try await Task.sleep(for: .milliseconds(250))  // let activation settle

        guard try await waitForOfferButton(in: axApp) != nil else {
            await restoreFocus(priorPID)
            throw AXError.offerButtonNotFound
        }

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
        // localized title — pressing an up-to-date button no-ops.
        guard let offer = mainOfferButton(in: axApp) else {
            await restoreFocus(priorPID)
            throw AXError.offerButtonNotFound
        }
        AXUIElementPerformAction(offer, kAXPressAction as CFString)
        onStage(.downloading(fraction: 0))

        // Download runs in the background now — hand focus back to the user.
        await restoreFocus(priorPID)

        try await driveToCompletion(
            axApp: axApp,
            store: store,
            bundleID: bundleID,
            appName: appName,
            appPath: appPath,
            baseline: baseline,
            onStage: onStage,
            confirmQuit: confirmQuit
        )
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

    /// Bring App Store to the front so an AXPress on its buttons registers. Resolve the
    /// app fresh from its pid inside the MainActor hop to avoid sending the non-Sendable
    /// `NSRunningApplication` across the actor boundary.
    private func activate(_ store: NSRunningApplication) async {
        let pid = store.processIdentifier
        await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    /// The pid of whatever app is frontmost right now, so we can restore it after a press.
    private func currentFrontmostPID() async -> pid_t? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    }

    /// Hand focus back to the app that was frontmost before we activated App Store.
    private func restoreFocus(_ pid: pid_t?) async {
        guard let pid else { return }
        await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -g: open/raise in the background, never steal focus from the user.
        process.arguments = ["-g", "macappstore://apps.apple.com/app/id\(trackID)"]
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

    /// The product page may take a moment to render after navigation; poll until
    /// the offer button appears (or give up).
    private func waitForOfferButton(in axApp: AXUIElement) async throws -> AXUIElement? {
        for _ in 0..<60 {  // ~12s
            if let offer = mainOfferButton(in: axApp) { return offer }
            try await Task.sleep(for: .milliseconds(200))
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
        store: NSRunningApplication,
        bundleID: String?,
        appName: String,
        appPath: URL,
        baseline: (short: String?, build: String?),
        onStage: @Sendable @escaping (InstallStage) -> Void,
        confirmQuit: @Sendable @escaping (String) async -> Bool
    ) async throws {
        var sheetTicks = 0
        var sawProgress = false   // the download actually started (vs. an immediate sheet)
        var continued = false     // we pressed Continue; the app is quitting + swapping
        var idleTicks = 0         // consecutive polls with no progress and no sheet
        var repressed = false     // we re-pressed Update once after an idle stretch

        // ~6 min hard cap of *polling* — the suspension on `confirmQuit` below doesn't
        // burn iterations, so waiting on the user's Relaunch tap never times us out.
        for _ in 0..<900 {
            // 1. Completion: the bundle on disk has been swapped for the new build.
            // Covers both the app-not-running case (installs directly, no sheet) and
            // the post-Continue swap. Keyed on short OR build version changing.
            if versionChanged(from: baseline, appPath: appPath) {
                onStage(.done)
                return
            }

            // 2. Sheet handling.
            let sheetPresent = quitSheet(in: axApp) != nil
            if sheetPresent {
                if continued {
                    // Already pressed Continue — the app is quitting and the swap is in
                    // flight. Ignore any lingering sheet and just wait for the version.
                } else if sawProgress, let bundleID, isRunning(bundleID) {
                    // Download finished, app still open → App Store's "Close this app to
                    // update" sheet. Gate it behind the user's Relaunch tap, then press
                    // Continue ourselves — we never quit the user's app behind their
                    // back. The press needs App Store frontmost (same as the offer
                    // press), so activate, press, then hand focus back. Re-find the
                    // sheet right before pressing: it can re-render across the await, and
                    // an AXPress on a stale ref silently no-ops.
                    guard await confirmQuit(appName) else {
                        let prior = await currentFrontmostPID()
                        await activate(store)
                        try await Task.sleep(for: .milliseconds(200))
                        if let fresh = quitSheet(in: axApp) {
                            pressSheetButton(fresh, "AXCancelButton")
                        }
                        await restoreFocus(prior)
                        throw AXError.cancelled
                    }
                    onStage(.installing)  // "Relaunching" — Continue quits + swaps in
                    let prior = await currentFrontmostPID()
                    await activate(store)
                    try await Task.sleep(for: .milliseconds(200))
                    if let fresh = quitSheet(in: axApp) {
                        pressSheetButton(fresh, "AXDefaultButton")  // Continue
                    }
                    await restoreFocus(prior)
                    continued = true
                    sheetTicks = 0
                } else {
                    // A sheet with no download behind it (or the app already gone) is a
                    // subscription / purchase / terms confirmation. Allow a couple of
                    // ticks in case it's transient, then bail and point the user at the
                    // App Store — never press a charge.
                    sheetTicks += 1
                    if sheetTicks >= 3 { throw AXError.needsManualConfirmation }
                }
            } else {
                sheetTicks = 0
            }

            // 3. Surface download progress from the offer button title (display only).
            // Once we've pressed Continue the title is meaningless, so stop reading it.
            if !continued, let offer = mainOfferButton(in: axApp), let title = title(offer) {
                if let fraction = Self.progressFraction(title) {
                    sawProgress = true
                    onStage(.downloading(fraction: fraction))
                } else if Self.isLoadingTitle(title) {
                    sawProgress = true
                    onStage(.downloading(fraction: 0))
                }
            }

            // 4. Fail-fast: if the press never took (no progress, no sheet), don't spin
            // the full 6-min cap holding the shared actor. After ~12s idle re-activate
            // and press once more; if still nothing ~12s later, give up so the next
            // update isn't blocked behind a dead one.
            if continued || sawProgress || sheetPresent {
                idleTicks = 0
            } else {
                idleTicks += 1
                if idleTicks == 30 && !repressed {
                    let prior = await currentFrontmostPID()
                    await activate(store)
                    try await Task.sleep(for: .milliseconds(250))
                    if let offer = mainOfferButton(in: axApp) {
                        AXUIElementPerformAction(offer, kAXPressAction as CFString)
                    }
                    await restoreFocus(prior)
                    repressed = true
                } else if idleTicks >= 60 {
                    throw AXError.timedOut
                }
            }

            try await Task.sleep(for: .milliseconds(400))
        }
        throw AXError.timedOut
    }

    /// Press a named button attribute on a sheet — `AXDefaultButton` (Continue) or
    /// `AXCancelButton` (Cancel). We reach the buttons through these role attributes
    /// because they're language-independent; the buttons' own identifiers are unstable
    /// `_NS:` values and their titles are localized.
    private func pressSheetButton(_ sheet: AXUIElement, _ attr: String) {
        guard let button = attribute(sheet, attr) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
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

    /// The product page's primary offer button. There can be several
    /// `AppStore.offerButton`s on a page (related apps, "more by this developer"),
    /// so we take the topmost (smallest y) — the page header's own button.
    private func mainOfferButton(in axApp: AXUIElement) -> AXUIElement? {
        var found: [AXUIElement] = []
        collect(axApp, id: "AppStore.offerButton", into: &found)
        return found.min { (frame($0)?.minY ?? .greatestFiniteMagnitude)
                         < (frame($1)?.minY ?? .greatestFiniteMagnitude) }
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
