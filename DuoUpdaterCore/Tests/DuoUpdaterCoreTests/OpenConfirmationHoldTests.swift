import AppKit
import CoreGraphics
import Testing
@testable import DuoUpdaterCore

/// `OpenConfirmationHold` — an app held at macOS's first-open prompt: not
/// finished launching, no window of its own, a quarantine without the
/// user-approved flag, and all three still so after a short re-check. Each
/// condition is there because something real broke the test without it; see
/// the type's documentation.
@Suite struct OpenConfirmationHoldTests {

    private typealias Reading = OpenConfirmationHold.Reading

    /// Conditions 1–3, every combination: held only when all three hold.
    /// Mutation: drop any one of them → a row here goes red.
    @Test(arguments: [false, true], [0, 3])
    func looksHeldOnlyWithAllThree(finished: Bool, windows: Int) {
        for pending in [false, true] {
            let reading = Reading(finishedLaunching: finished, windows: windows, quarantinePending: pending)
            #expect(reading.looksHeld == (!finished && windows == 0 && pending),
                    "finished=\(finished) windows=\(windows) pending=\(pending)")
        }
    }

    /// The fake processes: each one's reading before and after the settle.
    private final class Fake: @unchecked Sendable {
        var settled = false
        var settles = 0
        let before: [Int: Reading]
        let after: [Int: Reading]
        init(before: [Int: Reading], after: [Int: Reading]) { self.before = before; self.after = after }
        func read(_ pid: Int) -> Reading { (settled ? after : before)[pid]! }
        func settle() async { settled = true; settles += 1 }
    }

    private static let held = Reading(finishedLaunching: false, windows: 0, quarantinePending: true)
    private static let up = Reading(finishedLaunching: true, windows: 3, quarantinePending: true)
    private static let unquarantined = Reading(finishedLaunching: false, windows: 0, quarantinePending: false)

    private func isHeld(_ fake: Fake, _ pids: [Int]) async -> Bool {
        await OpenConfirmationHold.isHeld(pids, read: fake.read, settle: fake.settle)
    }

    /// Condition 4: held at both readings → held.
    @Test func heldAtBothReadingsIsHeld() async {
        let fake = Fake(before: [1: Self.held], after: [1: Self.held])
        #expect(await isHeld(fake, [1]))
        #expect(fake.settles == 1)
    }

    /// A slow launch caught mid-launch: held at the first reading, finished at
    /// the re-check → not held, and the restart goes on as before.
    /// Mutation: return after the first reading → red.
    @Test func heldFirstButFinishedAtTheRecheckIsNotHeld() async {
        let finished = Reading(finishedLaunching: true, windows: 0, quarantinePending: true)
        let fake = Fake(before: [1: Self.held], after: [1: finished])
        #expect(!(await isHeld(fake, [1])))
        let windowed = Reading(finishedLaunching: false, windows: 1, quarantinePending: true)
        #expect(!(await isHeld(Fake(before: [1: Self.held], after: [1: windowed]), [1])))
        let approved = Reading(finishedLaunching: false, windows: 0, quarantinePending: false)
        #expect(!(await isHeld(Fake(before: [1: Self.held], after: [1: approved]), [1])))
    }

    /// Nothing reads held the first time: no wait, not held — the census's
    /// daemons and the slow launch the review measured both land here or above.
    /// Mutation: always settle → `settles == 1`, red.
    @Test func nothingHeldAtFirstCostsNoWait() async {
        let fake = Fake(before: [1: Self.up, 2: Self.unquarantined], after: [1: Self.held, 2: Self.held])
        #expect(!(await isHeld(fake, [1, 2])))
        #expect(fake.settles == 0)
        #expect(!(await isHeld(Fake(before: [:], after: [:]), [])))
    }

    /// One held instance among several is enough: the quit would reach it too.
    /// Only an instance held at the first reading counts at the second.
    @Test func oneHeldInstanceIsEnoughButOnlyTheSameOne() async {
        #expect(await isHeld(Fake(before: [1: Self.up, 2: Self.held], after: [1: Self.up, 2: Self.held]), [1, 2]))
        #expect(!(await isHeld(Fake(before: [1: Self.up, 2: Self.held], after: [1: Self.held, 2: Self.up]), [1, 2])))
    }

    /// The flags field: 0x40 is "the user approved this copy".
    /// Mutation: test 0x40 the other way round, or treat absent as pending → red.
    @Test func quarantinePendingReadsTheApprovedFlag() {
        #expect(OpenConfirmationHold.quarantinePending("0181;6730f2a1;Homebrew Cask;"))
        #expect(!OpenConfirmationHold.quarantinePending("01c1;6730f2a1;Homebrew Cask;"))
        #expect(OpenConfirmationHold.quarantinePending("0083;00000000;Safari;"))
        #expect(!OpenConfirmationHold.quarantinePending(nil))
        #expect(!OpenConfirmationHold.quarantinePending(""))
        #expect(!OpenConfirmationHold.quarantinePending("zz;1;2"))
    }

    /// The live xattr read, on a scratch bundle directory.
    @Test func quarantineValueReadsTheBundlesOwnAttribute() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-hold-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(OpenConfirmationHold.quarantineValue(dir) == nil)
        let value = "0181;6730f2a1;Homebrew Cask;"
        let set = value.withCString { setxattr(dir.path, "com.apple.quarantine", $0, strlen($0), 0, XATTR_NOFOLLOW) }
        try #require(set == 0)
        #expect(OpenConfirmationHold.quarantineValue(dir) == value)
    }

    /// The `NSRunningApplication` adapter asks each source about this very
    /// process and uses the answers as given. Mutation: hard-code the window
    /// count, or skip the quarantine → red.
    @Test func theAdapterReadsThisProcessesOwnPidAndBundle() {
        let me = NSRunningApplication.current
        var askedPid: pid_t?
        var askedBundle: URL?
        let reading = OpenConfirmationHold.reading(
            of: me,
            windows: { askedPid = $0; return 5 },
            quarantine: { askedBundle = $0; return "0181;0;x;" })
        // The instance's own pid. Not `getpid()`: under the SwiftPM test helper
        // `NSRunningApplication.current` did not report it (observed here).
        #expect(askedPid == me.processIdentifier)
        #expect(reading.windows == 5)
        #expect(reading.finishedLaunching == me.isFinishedLaunching)
        if let bundle = me.bundleURL {
            #expect(askedBundle == bundle)
            #expect(reading.quarantinePending)
        } else {
            #expect(askedBundle == nil)
            #expect(!reading.quarantinePending)
        }
        let none = OpenConfirmationHold.reading(of: me, windows: { _ in 0 }, quarantine: { _ in nil })
        #expect(none.windows == 0)
        #expect(!none.quarantinePending)
    }

    /// The same adapter with a bundle, which the test process lacks: the
    /// bundle's own quarantine decides, and the pid's own window count.
    /// Mutation: skip the quarantine, or hard-code the windows → red.
    @Test func theAdapterAsksTheBundlesQuarantine() {
        let bundle = URL(fileURLWithPath: "/ZZFixture-hold/Held.app")
        var askedBundle: URL?
        let held = OpenConfirmationHold.reading(
            finishedLaunching: false, pid: 4242, bundle: bundle,
            windows: { $0 == 4242 ? 0 : 9 },
            quarantine: { askedBundle = $0; return "0181;0;Homebrew Cask;" })
        #expect(askedBundle == bundle)
        #expect(held == OpenConfirmationHold.Reading(finishedLaunching: false, windows: 0, quarantinePending: true))
        #expect(held.looksHeld)
        let approved = OpenConfirmationHold.reading(
            finishedLaunching: false, pid: 4242, bundle: bundle,
            windows: { _ in 0 }, quarantine: { _ in "01c1;0;Homebrew Cask;" })
        #expect(!approved.looksHeld)
    }

    /// `ownedWindowCount` counts windows of the asked pids only, offscreen
    /// included. Needs a window-server session, so skipped without one.
    /// Mutation: drop the pid filter → the unrelated pid counts the window, red.
    @MainActor
    @Test(.enabled(if: CGSessionCopyCurrentDictionary() != nil))
    func ownedWindowCountCountsThisProcessesOffscreenWindow() {
        #expect(StagedRelaunch.ownedWindowCount(pids: []) == 0)
        let before = StagedRelaunch.ownedWindowCount(pids: [getpid()])
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 10, height: 10),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(StagedRelaunch.ownedWindowCount(pids: [getpid()]) > before)
        #expect(StagedRelaunch.ownedWindowCount(pids: [pid_t(Int32.max)]) == 0)
    }
}
