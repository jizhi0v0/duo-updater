import Foundation

/// Whether finishing an install has to remember to reopen the app afterwards.
///
/// Most routes never need this: we quit the app ourselves and relaunch it
/// ourselves, so the reopen is part of the restart we already perform. The App
/// Store route is different — **the store quits a running app to replace its
/// bundle, and does not reliably bring it back**. Measured 2026-08-22, it did
/// not (DingTalk, and LocalSend through `mas` despite the store's dialog saying
/// it would):
///
/// ```
/// storedownloadd  AppHelper: Attempting to terminate <… com.dingtalk.mac - 58201>
/// loginwindow     CAS notification for appDeath for … /Applications/DingTalk.app
/// lsd             Building bundle record for app          ← new bundle lands
/// DuoUpdater      install done: DingTalk now 8.5.0        ← 35s later
/// ```
///
/// Measured 2026-09-16 on macOS 26.6 through the App Store GUI, it did: after a
/// Continue in App Store's own sheet, appstoreagent logged
/// `Relaunching terminated app after update` for both Excel and Word, 12.8 s
/// after our installer saw the bundle change — so our reopen, which runs on
/// that change, still found the app closed. The arming is kept because the
/// first case has no other way back.
///
/// That terminate is not something we asked for and not something we can
/// observe reliably: whether it lands before or after our post-install rescan
/// decides which of two faces the bug wears — the app already gone (the row
/// settles to "Updated ✓" with no restart offered at all) or the app still up
/// (a Restart badge appears, then clears itself the moment the store gets
/// around to the quit). Both end with the user's running app closed and
/// nothing recorded that it should come back.
///
/// The reopen machinery for this already exists — `reopenAfterQuit`, the
/// `QuitHandoff` relay, and the terminate observer that settles it. The gap was
/// only in *arming*: it used to happen exclusively when the user answered our
/// own quit-to-install prompt, which leaves out both the user answering App
/// Store's identical sheet themselves and the `mas` route, which raises no
/// sheet at all. Consent is not the signal. **Whether the app was running when
/// the install started is the signal**, because on this route that is precisely
/// the app the store is about to close.
public enum AppStoreQuitPolicy {

    /// True when the install must arm a reopen for `route`.
    ///
    /// Deliberately narrow. Arming a route we relaunch ourselves would race our
    /// own `restart()` and could open the app twice, so this stays false for
    /// every route whose quit we own.
    public static func armsReopen(
        route: InstallCoordinator.Route,
        wasRunningBeforeInstall: Bool
    ) -> Bool {
        route == .appStore && wasRunningBeforeInstall
    }
}
