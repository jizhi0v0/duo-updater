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
/// How it works (all of this was verified to need neither cursor movement nor
/// focus stealing):
///   1. `open -g macappstore://apps.apple.com/app/id<trackID>` — opens/navigates
///      the product page *in the background* (`-g` = don't activate). App Store
///      processes the deep link and renders the page without coming to the front.
///   2. Find the product page's offer button — a stable `AXIdentifier` of
///      `AppStore.offerButton` (the visible title is localized: Update / Open /
///      Get / …, so we never match on it; we already know an update is due).
///   3. `AXPress` it. The button's title then reports live progress as
///      "`N% loaded`", which we parse into `InstallStage.downloading`.
///   4. If the app is running, App Store raises an `AXSheet` ("Close This App to
///      Update" / Continue · Cancel). We do **not** press Continue ourselves —
///      we await `confirmQuit`, so the UI can gate it behind a Relaunch tap.
///      Continue is found via the sheet's `AXDefaultButton` (language-independent;
///      the buttons' own identifiers are unstable `_NS:` values).
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
        try navigateToProductPage(trackID: trackID)

        // Wait for App Store to be running and the product page's offer button to
        // populate. The page loads asynchronously after the deep link.
        let store = try await waitForAppStore()
        let axApp = AXUIElementCreateApplication(store.processIdentifier)
        guard try await waitForOfferButton(in: axApp) != nil else {
            throw AXError.offerButtonNotFound
        }

        // If the app is running, updating it via App Store would otherwise pop a
        // "Close this app to update" sheet whose Continue we'd have to press. We do
        // NOT play that game: App Store sheets also include subscription / purchase
        // confirmations (Termius, Microsoft 365…), and we must never auto-press a
        // financial confirmation. Instead we *quit the app ourselves* first (the user
        // already consented via the Relaunch affordance), then update it while it's
        // not running — which installs directly, with no sheet at all (verified).
        if let bundleID, isRunning(bundleID) {
            guard await confirmQuit(appName) else { throw AXError.cancelled }
            onStage(.installing)  // "preparing" — the app is quitting
            await terminateAndWait(bundleID: bundleID)
            // The page re-renders while the app quits, so let it settle.
            try? await Task.sleep(for: .milliseconds(800))
        }

        // Baseline the on-disk version *before* pressing, so completion is gated on
        // the bundle actually changing (see driveToCompletion) rather than on the
        // localized button title — which, for a fast download, flips back to a
        // non-progress state before storedownloadd has swapped the bundle in.
        let baseline = currentShortVersion ?? installedShortVersion(appPath)

        // Re-find the offer button *now*, right before pressing: the element captured
        // above goes stale across navigation + the app quitting, and an AXPress on a
        // dead reference silently no-ops (the symptom: progress sits at 0%, nothing
        // downloads). We already know (from detection) an update is due, so press
        // regardless of the localized title — pressing an up-to-date button no-ops.
        guard let offer = mainOfferButton(in: axApp) else { throw AXError.offerButtonNotFound }
        AXUIElementPerformAction(offer, kAXPressAction as CFString)
        onStage(.downloading(fraction: 0))

        try await driveToCompletion(axApp: axApp, appPath: appPath, baseline: baseline, onStage: onStage)
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Ask every running instance to quit (graceful `terminate()`, so the app can run
    /// its own save/quit prompt — which the user then handles), and wait up to ~12s
    /// for them to actually exit. If one refuses (e.g. the user cancels its prompt),
    /// we proceed anyway: pressing Update with it still up surfaces a sheet, which
    /// `driveToCompletion` reports as needing manual confirmation rather than forcing.
    private func terminateAndWait(bundleID: String) async {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
        for _ in 0..<60 {  // ~12s
            if !isRunning(bundleID) { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The bundle's `CFBundleShortVersionString` read straight from disk, used to
    /// detect when storedownloadd has finished swapping the new build in.
    private func installedShortVersion(_ appPath: URL) -> String? {
        let plist = appPath.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
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

    /// After pressing Update (with the app already quit), poll until the install
    /// lands — detected by the on-disk bundle version changing from `baseline`, the
    /// authoritative, language-independent signal. We never press any sheet button:
    /// if a sheet appears it's a subscription / purchase / terms confirmation (the
    /// app isn't running, so the "close to update" sheet can't), which we surface as
    /// `.needsManualConfirmation` rather than ever auto-confirming a charge.
    private func driveToCompletion(
        axApp: AXUIElement,
        appPath: URL,
        baseline: String?,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        var sheetTicks = 0

        for _ in 0..<900 {  // ~6 min hard cap
            // 1. Completion: the bundle on disk has been swapped for the new build.
            if let now = installedShortVersion(appPath), now != baseline {
                onStage(.done)
                return
            }

            // 2. A sheet means App Store wants a confirmation we won't auto-give
            // (subscription / purchase / terms). Allow a couple of ticks in case it's
            // transient, then bail and point the user at the App Store — never press it.
            if quitSheet(in: axApp) != nil {
                sheetTicks += 1
                if sheetTicks >= 3 { throw AXError.needsManualConfirmation }
            } else {
                sheetTicks = 0
            }

            // 3. Surface download progress from the offer button title (display only).
            if let offer = mainOfferButton(in: axApp), let title = title(offer) {
                if let fraction = Self.progressFraction(title) {
                    onStage(.downloading(fraction: fraction))
                } else if Self.isLoadingTitle(title) {
                    onStage(.downloading(fraction: 0))
                }
            }

            try await Task.sleep(for: .milliseconds(400))
        }
        throw AXError.timedOut
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
