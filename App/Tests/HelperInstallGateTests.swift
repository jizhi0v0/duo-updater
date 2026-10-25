import DuoUpdaterCore
import Foundation
import Testing

/// `HelperInstallGate`: the app hands `installMASApp` — root running `mas` — only
/// to a helper that declares it verifies `mas` first (protocol revision 3, #1659).
/// Security review 2026-10-25, item R6.
///
/// What this cannot cover is the wiring: that `HelperShellRunner.installMAS` asks
/// the gate before it sends, which needs the installed daemon (real-machine step).
@Suite struct HelperInstallGateTests {

    /// v0.5.14 reports revision 2 and runs `mas` out of the user-writable bundle.
    ///
    /// Mutation: lower `verifiedMASInstall` to 2 — this reply is then let through.
    @Test func theReleasedRevisionTwoHelperIsRefused() {
        let reply = "121 protocol/2"
        #expect(!HelperProtocolRevision.supportsVerifiedMASInstall(versionReply: reply))
        #expect(throws: MASInstaller.MASError.self) { try HelperInstallGate.require(versionReply: reply) }
    }

    /// Helpers from before revisions existed reply with the bare bundle version.
    @Test func aHelperWithoutARevisionIsRefused() {
        for reply in ["121", "0", "", "121 protocol/", "121 protocol/x", "121 protocol/0"] {
            #expect(throws: MASInstaller.MASError.self) { try HelperInstallGate.require(versionReply: reply) }
        }
    }

    /// The refusal is `helperOutdated` — not the silence or approval errors, which
    /// send the user somewhere else — and it names the restart the row offers.
    @Test func theRefusalIsTheOutdatedErrorWithTheRestartRemedy() {
        do {
            try HelperInstallGate.require(versionReply: "121 protocol/2")
            Issue.record("expected a refusal")
        } catch let error as MASInstaller.MASError {
            guard case .helperOutdated = error else { Issue.record("wrong error: \(error)"); return }
            #expect(!error.isHelperApproval)
            #expect(!error.isHelperUnresponsive)
            #expect(error.errorDescription?.contains(MASInstaller.MASError.helperRestartHint) == true)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    /// This build's own helper, and anything newer, is let through. Guards the
    /// first-build property: the helper that carries `stageVerifiedMAS` reports a
    /// revision that satisfies the gate.
    @Test func thisBuildsHelperAndNewerPass() throws {
        try HelperInstallGate.require(
            versionReply: HelperProtocolRevision.versionReply(bundleVersion: "121"))
        try HelperInstallGate.require(versionReply: "121 protocol/\(HelperProtocolRevision.current + 1)")
        #expect(HelperProtocolRevision.current >= HelperProtocolRevision.verifiedMASInstall)
    }
}
