import AppKit
import CoreGraphics
import Foundation

/// An app held at macOS's first-open prompt ("X is an app downloaded from the
/// Internet. Are you sure you want to open it?").
///
/// Until the user clicks Open the process exists — `NSRunningApplication`
/// lists it, so a restart finds it — but it is held: it does not answer a quit
/// request, and the restart used to wait that out and call it "likely a save
/// prompt". Measured 2026-10-22 on macOS 27.2 with a cask fresh from
/// `brew install --cask` (quarantine `0181`, no user-approved bit), at t+4 s
/// and t+12 s: `isFinishedLaunching` false and no window of its own in
/// `CGWindowListCopyWindowInfo(.optionAll)`. After the user clicked Open, the
/// same pid read finished and owned 7 windows (quarantine `01c1`).
///
/// **All four conditions, each one there because a census or a probe broke
/// the test without it** (2026-10-22):
///  1. **Not finished launching** and 2. **no window of its own.** Neither
///     alone: ImageOptim's first window (0.25–0.28 s) came before it finished
///     launching (0.37–0.40 s), and a hidden or windowless app has none.
///  3. **Its bundle carries `com.apple.quarantine` without the user-approved
///     flag (0x40).** Without it, 52 of 190 running processes on a Mac read
///     (1)+(2) permanently — daemons, XPC services, widgets, input-method
///     services (`SogouServices`), apps that never run `NSApplication` (Apple:
///     "Some applications do not post this notification … and so are never
///     reported as finished launching"). None of the 52 was quarantined. Not
///     enough on its own: 7 apps in /Applications carried `0181` though some
///     had been opened (AirCard, last used 2026-10-07).
///  4. **Still so after `recheckDelay`.** Without it, a quarantined app that
///     is merely slow to launch is caught mid-launch: a synthetic app busy 8 s
///     before `NSApp.run` read held at t=2 s, while the pre-change restart
///     queued its quit, which was delivered right after `didFinishLaunching`,
///     and relaunched it (16.4 s, `relaunched(true)`). Normal launches
///     measured finish in ≤0.75 s; the prompt holds indefinitely. A launch
///     slower than the delay with no window yet still reads held — UNVERIFIED
///     how common that is (heavy apps such as Xcode were not measured).
///
/// Judged per process: with two apps held at once only one prompt window was
/// on screen, while each app's own reading was right. Only an instance that
/// read held the first time is read again.
///
/// Apps DuoUpdater installed itself carry no quarantine (`InPlaceSwap` strips
/// it), so this only ever concerns copies installed some other way.
public enum OpenConfirmationHold {

    /// How long a first "held" reading has to last. Normal launches measured
    /// finish in ≤0.75 s; ~2 s leaves room for load.
    public static let recheckDelay: Duration = .seconds(2)

    /// One process's reading.
    public struct Reading: Sendable, Equatable {
        public let finishedLaunching: Bool
        /// Windows the process owns, on screen or not (`ownedWindowCount`).
        public let windows: Int
        /// Its bundle carries `com.apple.quarantine` without the
        /// user-approved flag (`quarantinePending`).
        public let quarantinePending: Bool

        public init(finishedLaunching: Bool, windows: Int, quarantinePending: Bool) {
            self.finishedLaunching = finishedLaunching
            self.windows = windows
            self.quarantinePending = quarantinePending
        }

        /// Conditions 1–3. Condition 4 is `isHeld`'s second reading.
        public var looksHeld: Bool { !finishedLaunching && windows == 0 && quarantinePending }
    }

    /// Whether any of `instances` is held: read held, and read held again
    /// after `settle` (the live one waits `recheckDelay`). One held instance is
    /// enough to stop a restart: its quit would reach that one too. `settle` is
    /// never called when nothing reads held the first time — the common case
    /// costs no wait.
    public static func isHeld<Instance>(
        _ instances: [Instance], read: (Instance) -> Reading, settle: () async -> Void
    ) async -> Bool {
        let suspects = instances.filter { read($0).looksHeld }
        guard !suspects.isEmpty else { return false }
        await settle()
        return suspects.contains { read($0).looksHeld }
    }

    /// `isHeld` over live processes.
    public static func isHeld(_ instances: [NSRunningApplication]) async -> Bool {
        await isHeld(instances, read: { reading(of: $0) }, settle: {
            // cancel-ok: a cancelled caller only re-reads sooner; nothing has been quit yet.
            try? await Task.sleep(for: recheckDelay)
        })
    }

    /// The live reading of one process. Each source is injectable, so a test
    /// can see that the process's own pid and bundle are what get asked.
    public static func reading(
        of instance: NSRunningApplication,
        windows: (pid_t) -> Int = { StagedRelaunch.ownedWindowCount(pids: [$0]) },
        quarantine: (URL) -> String? = quarantineValue
    ) -> Reading {
        reading(
            finishedLaunching: instance.isFinishedLaunching, pid: instance.processIdentifier,
            bundle: instance.bundleURL, windows: windows, quarantine: quarantine)
    }

    /// `reading(of:)` from the instance's fields, so a test can pass a bundle
    /// (the test process has none).
    static func reading(
        finishedLaunching: Bool, pid: pid_t, bundle: URL?,
        windows: (pid_t) -> Int, quarantine: (URL) -> String?
    ) -> Reading {
        Reading(
            finishedLaunching: finishedLaunching,
            windows: windows(pid),
            quarantinePending: quarantinePending(bundle.flatMap(quarantine)))
    }

    /// Whether a `com.apple.quarantine` value marks a copy macOS has not been
    /// told to open yet: present, with the user-approved flag (0x40) clear in
    /// its leading hex field (`0181;…` vs `01c1;…`). Absent or unparsable →
    /// false: the narrow side, which leaves the restart as it was before this
    /// existed.
    public static func quarantinePending(_ value: String?) -> Bool {
        guard let field = value?.split(separator: ";", omittingEmptySubsequences: false).first,
              let flags = UInt32(field, radix: 16) else { return false }
        return flags & 0x40 == 0
    }

    /// The `com.apple.quarantine` value on the bundle itself (symlinks not
    /// followed), or nil when it has none or it cannot be read.
    public static func quarantineValue(_ bundle: URL) -> String? {
        let path = bundle.path
        let size = getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, "com.apple.quarantine", &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return nil }
        return String(decoding: buffer.prefix(read), as: UTF8.self)
    }
}
