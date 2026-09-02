import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite("Row version-line precedence")
struct RowVersionLineTests {
    private let staged = StagedSelfUpdate(
        version: "26.9.2", buildVersion: "802",
        stagedBundlePath: URL(fileURLWithPath: "/tmp/Eudic.app"))

    /// Regression for #210: Eudic is ahead of the lagging feed, but the process is
    /// still on 26.8.3. The Relaunch action has to be explained by 26.8.3 → 26.9.1;
    /// the action-less 26.9.1 ↓ 26.9.0 note is secondary.
    @Test("restart outranks a lagging-feed downgrade note")
    func restartBeatsDowngrade() {
        let from = VersionSide(marketing: "26.8.3")
        #expect(RowVersionLine.state(
            staged: nil,
            pendingBatchRestartMarketing: nil,
            restartFrom: from,
            downgradeVersion: "26.9.0") == .restart(from: from))
    }

    /// Before the post-batch process sweep, the provisional restart fact carries
    /// the same user action and therefore has the same priority.
    @Test("a deferred batch restart also outranks the downgrade note")
    func batchRestartBeatsDowngrade() {
        #expect(RowVersionLine.state(
            staged: nil,
            pendingBatchRestartMarketing: "26.8.3",
            restartFrom: nil,
            downgradeVersion: "26.9.0")
            == .restart(from: VersionSide(marketing: "26.8.3")))
    }

    /// The app's already-downloaded latest remains the most concrete next action.
    @Test("a staged relaunch keeps first priority")
    func stagedBeatsRestart() {
        #expect(RowVersionLine.state(
            staged: staged,
            pendingBatchRestartMarketing: "26.8.3",
            restartFrom: VersionSide(marketing: "26.8.3"),
            downgradeVersion: "26.9.0") == .stagedRelaunch(staged))
    }

    /// The downgrade note is still useful when no relaunch fact supersedes it.
    @Test("the downgrade note remains for an action-less row")
    func downgradeRemainsWithoutAction() {
        #expect(RowVersionLine.state(
            staged: nil,
            pendingBatchRestartMarketing: nil,
            restartFrom: nil,
            downgradeVersion: "26.9.0") == .downgrade(to: "26.9.0"))
        #expect(RowVersionLine.state(
            staged: nil,
            pendingBatchRestartMarketing: nil,
            restartFrom: nil,
            downgradeVersion: nil) == .status)
    }
}
