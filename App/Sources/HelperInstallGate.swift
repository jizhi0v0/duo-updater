import DuoUpdaterCore
import Foundation

/// Whether the helper that answered `helperVersion` may be handed an install.
///
/// `installMASApp` makes the helper run `mas` as root. A helper built before
/// `HelperService.stageVerifiedMAS` runs `Contents/Resources/mas` straight out of
/// the app bundle, which a process of this user can overwrite — so the app must
/// not send it the request, however it came to be the one answering (an in-place
/// update leaves the previous process holding launchd's slot for up to its idle
/// window, and for good on builds that predate `IdleExit`). Foundation and Core
/// only so the test bundle can run it without XPC.
enum HelperInstallGate {
    /// Throws `helperOutdated` unless `versionReply` declares a helper that
    /// verifies `mas` first. An unreadable reply reads as revision 1, so it can
    /// only ever refuse.
    static func require(versionReply: String) throws {
        guard HelperProtocolRevision.supportsVerifiedMASInstall(versionReply: versionReply) else {
            throw MASInstaller.MASError.helperOutdated
        }
    }
}
