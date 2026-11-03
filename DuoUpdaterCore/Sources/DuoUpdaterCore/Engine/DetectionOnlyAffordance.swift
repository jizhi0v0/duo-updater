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
/// This type owns the *decision* — is there a page to send the user to, and is
/// it a web page or the app's own deep link — and the copy for the case every
/// host renders identically. It deliberately does not own a title for the two
/// page cases: that is each host's call.
///
/// How the URL is opened used to be each host's call too, and the hosts
/// disagreed: the popover handed a non-http(s) scheme to the app itself, the
/// workbench gave it to a plain `NSWorkspace.open`. `.openInApp` is that
/// decision, made here once (`RowActionControls`).
public enum DetectionOnlyAffordance: Sendable, Equatable {
    /// A web page to send the user to — the vendor's download or release page.
    case openPage(URL)
    /// An app-internal deep link (Chrome's `chrome://settings/help`), handed to
    /// THIS copy of the app (`NSWorkspace.open(_:withApplicationAt:)`) so it
    /// acts through its own update channel — for Chrome, opening that page
    /// starts a Keystone check and download. A plain `open` would leave the
    /// choice of app to whatever claims the scheme, which need not be this copy,
    /// or anything. Same hand-off `AppListModel.openSelfUpdater` makes.
    case openInApp(URL)
    /// A deep link owned by ANOTHER app, opened through LaunchServices so the
    /// scheme's registered handler takes it. Setapp's
    /// `setapp://install?app_id=…` is the case, and the distinction is measured:
    /// handing the same URL to the client by path
    /// (`open(_:withApplicationAt:)`) only activates Setapp on its home page,
    /// while a plain `open` reaches the agent that owns the scheme and lands on
    /// the app's page ("App is Already Installed — open it?" for a copy that is
    /// there). It does not install.
    case openDeepLink(URL)
    /// No page at all. The only honest offer left is showing the user where the
    /// app lives, so they can deal with it by hand — every host renders this the
    /// same way, so its copy lives here.
    case revealInFinder

    public static func resolve(pageURL: URL?) -> Self {
        resolve(pageURL: pageURL, setappClient: setappClientURL())
    }

    /// The decision with the client lookup already done, so a test can speak for
    /// both a Mac with Setapp and one without.
    static func resolve(pageURL: URL?, setappClient: URL?) -> Self {
        guard let pageURL else { return .revealInFinder }
        if pageURL.scheme == "setapp" {
            // Setapp's scheme is registered by its agent, and the client is the
            // app that services it. Without the client installed there is no one
            // to hand it to, and a `setapp://` URL opened by LaunchServices would
            // at best be a no-op — reveal the copy instead of pretending.
            return setappClient != nil ? .openDeepLink(pageURL) : .revealInFinder
        }
        if let scheme = pageURL.scheme, scheme != "http", scheme != "https" {
            return .openInApp(pageURL)
        }
        return .openPage(pageURL)
    }

    /// Setapp ships into one of two documented roots, depending on the account:
    /// `/Applications/Setapp.app` for an admin account, `~/Applications` for a
    /// standard one ([Fixing permissions errors](https://support.setapp.com/hc/en-us/articles/360010208439-Fixing-permissions-errors-in-Setapp)).
    /// Kept as a name here because callers reach for it through this type;
    /// `SetappAutomation` is where the lookup lives.
    static func setappClientURL() -> URL? { SetappAutomation.clientURL() }

    /// Localized title for the `.revealInFinder` case only. The page cases have
    /// no shared title on purpose — see the type doc.
    public static var revealInFinderTitle: String {
        String(localized: "Reveal in Finder")
    }
}
