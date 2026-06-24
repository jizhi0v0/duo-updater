import Foundation

/// XPC interface the privileged helper (`com.duoupdater.helper`) exposes to the
/// main app. The helper is an `SMAppService` LaunchDaemon running as **root**, so
/// it can grant the privilege `mas install` needs without the per-install
/// `osascript … with administrator privileges` password prompt.
///
/// This single file is compiled into BOTH the app target and the helper target
/// (it must stay Foundation-only — no app types). The interface is deliberately
/// *structured*, never a free-form command string: the helper builds the shell
/// command itself from these validated parameters, so a caller can never ask the
/// root helper to run arbitrary code.
@objc protocol MASHelperProtocol {
    /// Install/update a Mac App Store app by its numeric adam (track) id, as root,
    /// re-associated into the calling user's GUI session (so `storedownloadd`
    /// actually transfers). The helper locates the `mas` binary relative to its
    /// own bundled location (`…/Contents/Resources/mas`) — no path is trusted from
    /// the client. `mas` output is written to `logPath` (which the app tails for
    /// live progress); the reply carries `mas`'s exit status and a stderr tail.
    func installMASApp(adamID: Int,
                       uid: Int,
                       gid: Int,
                       userName: String,
                       logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void)

    /// The helper's bundle version, so the app can detect a stale installed helper
    /// and re-register a newer build.
    func helperVersion(withReply reply: @escaping (String) -> Void)
}
