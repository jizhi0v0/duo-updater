import AppKit
import ApplicationServices

/// Closes a *specific* window of macOS's Installer.app — the one showing a package
/// we handed over earlier and the user never finished.
///
/// Why this exists: a `pkg` update opens an Installer window and then waits for the
/// user. If they walk away and a newer release arrives, installing that one opens a
/// second window (different file = different document), and the windows pile up
/// until the user notices. Verified on macOS 27: two `open` calls on two packages
/// leave two windows, while re-opening the *same* package only brings the existing
/// window forward.
///
/// Two deliberate restraints:
///
/// - We never quit Installer.app and never touch a window we can't positively
///   identify. Windows are matched by `AXDocument` — the exact file URL — not by
///   title, which comes from the package's own metadata and can collide between
///   versions of the same product.
/// - We press the close button and then *check the window actually went away*. A
///   window that's mid-install (or showing an authorization sheet) is expected to
///   refuse or to put up a confirmation; we treat "still there" as "the user is
///   using it" and leave it alone rather than hunting for a confirm button.
public enum InstallerWindowCloser {

    static let installerBundleID = "com.apple.installer"

    /// Ask Installer.app to close the window showing `package`.
    ///
    /// Returns `true` only when the window was found *and* is gone afterwards, so
    /// the caller can treat a `true` as "nothing is reading that file any more".
    /// Returns `false` for every other outcome — Installer isn't running, we don't
    /// hold Accessibility trust, no window matches, or the window declined to close.
    @discardableResult
    public static func closeWindow(showing package: URL) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: installerBundleID)
        guard !running.isEmpty else { return false }

        let apps = running.map { AXUIElementCreateApplication($0.processIdentifier) }
        guard let (axApp, window) = await locate(package, in: apps) else { return false }
        guard let closeButton = attribute(window, "AXCloseButton") else { return false }

        // Don't touch a window the user is actually using. Both checks are
        // pre-flight — see `isInstalling` / `isAuthorizationPromptUp` for what each
        // one can and can't see.
        if isInstalling(window: window, closeButton: closeButton) {
            Log.install.info(
                "left installer window alone, install in progress: \(package.lastPathComponent, privacy: .public)")
            return false
        }
        if isAuthorizationPromptUp() {
            Log.install.info(
                "left installer window alone, authorization prompt up: \(package.lastPathComponent, privacy: .public)")
            return false
        }

        AXUIElementPerformAction(closeButton, kAXPressAction as CFString)

        // Closing is animated, so re-check after a beat rather than immediately.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if self.window(in: axApp, showing: package) != nil {
            Log.install.info(
                "installer window still open after close (busy?): \(package.lastPathComponent, privacy: .public)")
            return false
        }
        Log.install.info(
            "closed stale installer window: \(package.lastPathComponent, privacy: .public)")
        return true
    }

    /// Find the window showing `package`, retrying briefly before giving up.
    ///
    /// The retry is load-bearing, not defensive padding: while Installer is busy
    /// opening a document, `AXDocument` reads come back empty for *every* one of its
    /// windows, so a single-shot lookup right after we opened the new package finds
    /// nothing and the stale window survives. Measured on macOS 27 — a probe that
    /// looked once failed 8/8 in a tight open-then-close loop, while the same
    /// windows read back correctly moments later.
    private static func locate(
        _ package: URL, in apps: [AXUIElement]
    ) async -> (AXUIElement, AXUIElement)? {
        for attempt in 0..<6 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
            for axApp in apps {
                if let window = window(in: axApp, showing: package) {
                    return (axApp, window)
                }
            }
        }
        return nil
    }

    /// Whether the window is mid-install.
    ///
    /// Installer disables the window's own close button for the whole install phase
    /// and re-enables it on the summary page (measured on macOS 27: `AXEnabled`
    /// false from pressing Install until "The installation was completed
    /// successfully"). Pressing it while disabled is a plain no-op — no sheet, no
    /// interruption — so this check is about *not poking* a busy window rather than
    /// about safety, which the disabled button already provides.
    private static func isInstalling(window: AXUIElement, closeButton: AXUIElement) -> Bool {
        bool(closeButton, kAXEnabledAttribute as String) == false
    }

    /// Whether an authorization prompt is on screen.
    ///
    /// The "Installer is trying to install new software" Touch ID/password dialog
    /// belongs to `SecurityAgent`, not to the Installer window: while it is up the
    /// window reports a *usable* close button and enabled Install/Go Back buttons,
    /// so nothing about the window itself gives this away. The agent process only
    /// exists while it has a prompt up, so its presence is the signal.
    ///
    /// It serves every app's authorization prompts, so this can back off for a
    /// prompt that has nothing to do with us. That trade is deliberate: the cost of
    /// a false positive is one skipped cleanup, and the cost of a false negative is
    /// yanking a window out from under someone who is authenticating.
    private static func isAuthorizationPromptUp() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.SecurityAgent").isEmpty
    }

    private static func window(in axApp: AXUIElement, showing package: URL) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { isSamePackage(document: string($0, "AXDocument"), as: package) }
    }

    /// Whether a window's `AXDocument` refers to `package`.
    ///
    /// `AXDocument` is a file URL string in whatever form the document was opened
    /// with, while our stored path comes from `FileManager.temporaryDirectory` — the
    /// two differ by symlinks (`/tmp` → `/private/tmp`, `/var` → `/private/var`) and
    /// by percent-encoding, so both sides are normalised before comparing.
    static func isSamePackage(document: String?, as package: URL) -> Bool {
        guard let document, !document.isEmpty else { return false }
        let documentURL = URL(string: document) ?? URL(fileURLWithPath: document)
        guard documentURL.isFileURL else { return false }
        return canonicalPath(documentURL) == canonicalPath(package)
    }

    private static func canonicalPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        // `resolvingSymlinksInPath` drops a leading `/private` only for a path that
        // exists on disk; do it unconditionally so a package already swept off disk
        // still compares equal to the window showing it.
        for root in ["/private/tmp", "/private/var"] where path.hasPrefix(root + "/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return (value as! AXUIElement?)
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
