import Foundation

/// What to offer for a result that's detection-only — we can tell the user an
/// update exists, but there's no artifact to install and no `vendorInstallerKind`
/// to route through. Both hosts (menu-bar popover and workbench window) hit this
/// tail case, and it isn't specific to any one source: any result whose remote
/// `pageURL` is nil lands here (`ElectronManifestSource` is just the first source
/// that hits it on every result, since it only ever has a release CDN directory,
/// not a page meant for people).
///
/// Before this type existed the two hosts each wrote their own fallback and they
/// disagreed — see issue #197: the popover offered a button labeled "Open" that
/// actually revealed the app in Finder (`NSWorkspace.activateFileViewerSelecting`),
/// while the workbench rendered nothing at all for the identical data.
///
/// This type only owns the *decision* (is there a page to send the user to, or
/// not) and the copy for the case both hosts render identically. It deliberately
/// does not own a title for `.openPage`, nor how a host actually opens that URL:
/// the popover's `openAction()` recognizes a non-http(s) scheme and hands it to
/// the app itself via `NSWorkspace.open(_:withApplicationAt:)` so the app's own
/// updater can act on it (e.g. Chrome's `chrome://` deep link); the workbench
/// does a plain `NSWorkspace.shared.open(url)` regardless of scheme. That gap
/// predates this type and is out of scope for #197 — each host still decides it.
public enum DetectionOnlyAffordance: Sendable, Equatable {
    /// There's a page URL to send the user to — the vendor's download/release
    /// page, or an app-internal deep link. What the button says and how the URL
    /// is opened are both a per-host call; see the type doc above.
    case openPage(URL)
    /// No page at all. The only honest offer left is showing the user where the
    /// app lives, so they can deal with it by hand — every host renders this the
    /// same way, so its copy lives here.
    case revealInFinder

    public static func resolve(pageURL: URL?) -> Self {
        pageURL.map(Self.openPage) ?? .revealInFinder
    }

    /// Localized title for the `.revealInFinder` case only. `.openPage` has no
    /// shared title on purpose — see the type doc.
    public static var revealInFinderTitle: String {
        String(localized: "Reveal in Finder")
    }
}
