import DuoUpdaterCore
import Foundation
import ServiceManagement
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

@MainActor
@Suite struct HelperApprovalTests {
    @Test func probesAfterApprovalAndHoldsOfferDuringAStatusRegression() async throws {
        let system = HelperStatusFixture(.requiresApproval)
        let (probes, observedProbe) = AsyncStream<Bool>.makeStream()
        var nextProbe = probes.makeAsyncIterator()
        let approvalTime = ContinuousClock.now
        let helper = PrivilegedHelperClient(
            readStatus: { await system.status },
            probe: { afterApproval in
                observedProbe.yield(afterApproval)
                return true
            },
            now: { approvalTime })
        defer { observedProbe.finish() }
        await helper.refreshStatusOffMain()
        helper.checkReachability()
        #expect(!helper.isCheckingReachability)
        #expect(helper.answering == nil)

        system.status = .enabled
        await helper.refreshStatusOffMain()
        #expect(await nextProbe.next() == true)
        #expect(helper.isEnabled)

        system.status = .requiresApproval
        await helper.refreshStatusOffMain()
        #expect(!helper.isEnabled)
        #expect(helper.isConfirmingApproval)
        #expect(helper.answering == nil)

        system.status = .enabled
        #expect(try await helper.requireApprovalForInstall())
        #expect(await nextProbe.next() == true)
        #expect(helper.isEnabled)
        #expect(!helper.isConfirmingApproval)
    }

    @Test func persistentRegressionStillBlocksInstall() async {
        let system = HelperStatusFixture(.requiresApproval)
        let approvalTime = ContinuousClock.now
        let helper = PrivilegedHelperClient(
            readStatus: { await system.status }, probe: { _ in true },
            retryDelay: .milliseconds(5), now: { approvalTime })
        await helper.refreshStatusOffMain()
        system.status = .enabled
        await helper.refreshStatusOffMain()
        system.status = .requiresApproval
        await #expect(throws: MASInstaller.MASError.self) {
            try await helper.requireApprovalForInstall()
        }
        #expect(!helper.isEnabled)
        #expect(!helper.isConfirmingApproval)
    }

    @Test func alreadyApprovedAtLaunchDoesNotStartFirstApprovalRetry() async throws {
        let helper = PrivilegedHelperClient(readStatus: { .enabled }, probe: { _ in true })
        let afterApproval = try await helper.requireApprovalForInstall()
        #expect(!afterApproval)
        #expect(!helper.isCheckingReachability)
        #expect(helper.answering == nil)
    }
}

@MainActor
private final class HelperStatusFixture {
    var status: SMAppService.Status

    init(_ status: SMAppService.Status) {
        self.status = status
    }
}

@Suite struct HelperHandshakeTests {
    private typealias MASError = MASInstaller.MASError
    private static let invalid = MASError.helperCommunication(
        .handshake, .xpc(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid))

    @Test func firstApprovalRetriesInvalidConnectionsAndReturnsTheSuccessfulProbe() async throws {
        var attempts = 0
        var approvalReads = 0
        let reply = try await HelperShellRunner.retryHandshake(
            afterApproval: true, retryDelay: .zero,
            isEnabled: {
                approvalReads += 1
                return true
            }
        ) {
            attempts += 1
            if attempts < 4 { throw Self.invalid }
            return "155 protocol/4"
        }
        #expect(reply == "155 protocol/4")
        #expect(attempts == 4)
        #expect(approvalReads == 3)
    }

    @Test func invalidConnectionStopsAfterThreeRetries() async {
        var attempts = 0
        await #expect(throws: MASError.self) {
            try await HelperShellRunner.retryHandshake(
                afterApproval: true, retryDelay: .zero, isEnabled: { true }
            ) {
                attempts += 1
                throw Self.invalid
            }
        }
        #expect(attempts == 4)
    }

    @Test func approvalRevokedBeforeARetryBlocksTheNextProbe() async {
        var attempts = 0
        do {
            try await HelperShellRunner.retryHandshake(
                afterApproval: true, retryDelay: .zero, isEnabled: { false }
            ) {
                attempts += 1
                throw Self.invalid
            }
            Issue.record("expected helper approval error")
        } catch MASError.helperNotApproved {
            #expect(attempts == 1)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func establishedApprovalAndOtherFailuresDoNotRetry() async {
        for (afterApproval, failure) in [
            (false, Self.invalid),
            (true, MASError.helperCommunication(.handshake, .timeout)),
            (true, MASError.helperCommunication(.handshake, .missingSigningRequirement)),
            (true, MASError.helperCommunication(
                .handshake, .xpc(domain: NSCocoaErrorDomain, code: NSXPCConnectionInterrupted))),
        ] {
            var attempts = 0
            await #expect(throws: MASError.self) {
                try await HelperShellRunner.retryHandshake(
                    afterApproval: afterApproval, retryDelay: .zero,
                    isEnabled: {
                        Issue.record("unexpected approval recheck")
                        return true
                    }
                ) {
                    attempts += 1
                    throw failure
                }
            }
            #expect(attempts == 1)
        }
    }
}
