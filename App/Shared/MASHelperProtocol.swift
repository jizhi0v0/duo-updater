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
    /// and re-register a newer build. Since protocol revision 2 the reply also
    /// carries the revision (`HelperProtocolRevision.versionReply`); a reply
    /// without one is revision 1.
    func helperVersion(withReply reply: @escaping (String) -> Void)

    /// The version strings of the app bundle Sparkle staged for `bundleID` in
    /// **root's** cache — the build an installer running as root will swap in on
    /// the app's next quit, which this user cannot read (`/var/root` is
    /// `drwxr-x--- root wheel`). Read-only, and as structured as the install call:
    /// the client names a bundle identifier, never a path. The helper builds the
    /// path itself, refuses an identifier outside `[A-Za-z0-9.-]`, follows no
    /// symlink, and answers with these three plist strings and nothing else.
    /// All nil for anything missing, unreadable, ambiguous or out of bounds
    /// (`StagedSparkleVersions.read`).
    ///
    /// Revision 2. A helper of revision 1 has no such selector; the app asks
    /// `helperVersion` first and treats it as not enabled.
    func stagedSparkleBundleVersions(bundleID: String,
                                     withReply reply: @escaping (_ identifier: String?,
                                                                 _ shortVersion: String?,
                                                                 _ buildVersion: String?) -> Void)
}

/// What an installed helper can do, told to the app through `helperVersion`.
///
/// Not the bundle version: that is the app's build number, which only moves at
/// release time, so a development build and the release before it report the
/// same number while one has a selector the other lacks. And the helper that
/// answers is not necessarily the one inside the current app bundle — a copy
/// launched before an in-place update keeps launchd's slot until it idles out
/// (`IdleExit` in main.swift), or for good on builds that predate that. Asking
/// such a copy for a selector it does not have gets the message dropped on its
/// side, so the app asks for the revision first and never sends a selector the
/// peer did not declare.
///
/// Bump `current` whenever a selector is added to `MASHelperProtocol`.
enum HelperProtocolRevision {
    /// This build's revision.
    static let current = 2
    /// The first revision that implements `stagedSparkleBundleVersions`.
    static let stagedSparkleBundleVersions = 2

    private static let marker = " protocol/"

    /// `helperVersion`'s reply: the bundle version as before, then the revision.
    /// Kept a superset of the old reply so an older app, which only waits for
    /// any reply at all (`HelperShellRunner.ensureReachable`), reads it the same.
    static func versionReply(bundleVersion: String) -> String {
        bundleVersion + marker + String(current)
    }

    /// Whether the helper that sent `versionReply` implements
    /// `stagedSparkleBundleVersions`. False for every helper built before it,
    /// which the caller treats exactly like a helper that is not enabled.
    static func supportsStagedSparkleBundleVersions(versionReply: String) -> Bool {
        revision(ofVersionReply: versionReply) >= stagedSparkleBundleVersions
    }

    /// The revision a `helperVersion` reply declares. 1 for a reply without
    /// one — every helper built before revisions existed — and for anything
    /// malformed, so an unreadable answer can only ever mean "can do less".
    static func revision(ofVersionReply reply: String) -> Int {
        guard let range = reply.range(of: marker, options: .backwards) else { return 1 }
        let digits = reply[range.upperBound...]
        guard !digits.isEmpty, digits.count <= 4,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(digits), value >= 1
        else { return 1 }
        return value
    }
}
