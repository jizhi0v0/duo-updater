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
public enum DetectionOnlyAffordance: Sendable, Equatable {
    /// There's somewhere to send the user — the vendor's page, or (when the URL's
    /// scheme isn't http/https) an app-internal deep link into its own updater.
    case openPage(URL)
    /// No page at all. The only honest offer left is showing the user where the
    /// app lives, so they can deal with it by hand.
    case revealInFinder

    public static func resolve(pageURL: URL?) -> Self {
        pageURL.map(Self.openPage) ?? .revealInFinder
    }

    /// Button title — matches what the action actually does, unlike the old
    /// popover behavior where a `pageURL == nil` result still said "Open".
    public var buttonTitle: String {
        switch self {
        case .openPage: return String(localized: "Open")
        case .revealInFinder: return String(localized: "Reveal in Finder")
        }
    }
}
