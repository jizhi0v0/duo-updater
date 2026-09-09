import AppKit
import Carbon

/// Makes an already-running app *become active* — so it runs whatever it does on
/// `applicationDidBecomeActive` — without raising its windows, without moving the
/// pointer, and without leaving the user's front app changed.
///
/// **Why this is needed at all.** The store `TestFlightInventory` reads is written
/// by TestFlight.app and by nothing else, and TestFlight only goes and asks the
/// server on two occasions: a cold launch, and becoming active. `TestFlightRefresh`
/// serves the first with a hidden background launch. The second is what this
/// serves, and it is the only thing that reaches a TestFlight that is **already
/// running** — measured four times: a background launch delivered to a running
/// TestFlight does nothing at all.
///
/// **What was measured, 2026-09-10, with two independent witnesses** (the store's
/// write-ahead log, and `lsof` sampling TestFlight's own sockets every 500ms):
///
/// | trigger | network | store | focus |
/// |---|---|---|---|
/// | cold hidden launch (control) | 6 connections | written | unchanged |
/// | **this, on a running instance** | **2 connections** | **written** | **unchanged** |
/// | `CGEventPostToPid` click | none | untouched | unchanged |
/// | `CGEventPostToPid` scroll | none | untouched | unchanged |
/// | AX `AXRaise` | none (returned -25205) | untouched | unchanged |
/// | AX `AXScrollDownByPage` | none (returned -25205) | untouched | unchanged |
///
/// The whole input-injection family is dead for this purpose, and the reason is the
/// same one that makes this type necessary: TestFlight's trigger is *activation*,
/// not user interaction, and posted input events do not make an app active.
///
/// **On the private symbols.** `_SLPSSetFrontProcessWithOptions` and friends live in
/// `SkyLight.framework`, which is private. They are resolved with `dlopen`/`dlsym`
/// and every failure degrades to ``Outcome/unavailable`` — never a crash, never a
/// wrong answer. Notarization does not inspect API surface (Apple: the notary
/// service "scans your software for malicious content, checks for code-signing
/// issues"; it "is not App Review"), and shipping Developer ID apps do exactly
/// this. The real cost is that there is no contract: a future macOS may remove
/// them, which is why the caller must treat `unavailable` as an ordinary answer.
///
/// **No new permission.** Measured 2026-09-10 by running this through
/// `launchctl submit`, which breaks the responsibility chain that would otherwise
/// lend it the parent's grant: with `AXIsProcessTrusted() == false` the activation
/// still succeeded and TestFlight still went to the network. This is the one way it
/// beats `CGEventPostToPid`, which Apple documents as requiring Accessibility.
public struct SilentActivation: Sendable {

    /// What one attempt did. Every case is something the caller may need to say out
    /// loud — a silent no-op would leave the user reading a stale version number
    /// believing it was just refreshed.
    public enum Outcome: Sendable, Equatable {
        /// The app was made active for `heldFor` and the previous state was restored.
        case activated(heldFor: Duration)
        /// SkyLight is not resolvable on this macOS. Not a failure to report as one.
        case unavailable
        /// A password field somewhere owns the keyboard; see ``refusedSecureInput``.
        case refusedSecureInput
        /// Nothing to activate — the app is not running.
        case notRunning
        /// The app is already the active one, so there is no activation to deliver.
        /// Measured 2026-09-10 with TestFlight frontmost: the front swap is a no-op
        /// and **no sync happens** — zero connections against the 2 that the same
        /// call makes on a background instance. Reported rather than swallowed,
        /// because "we nudged it and nothing changed" would be a lie about a nudge
        /// that never landed.
        case alreadyActive
        /// SkyLight was there and said no.
        case failed(code: Int32)
    }

    /// How long the app stays front.
    ///
    /// ⚠️ **This window is real**: keystrokes during it go to the activated app, not
    /// to whatever the user was typing in. Measured 2026-09-10 against the store's
    /// write-ahead log: a 120ms hold syncs, a ~50ms hold produced a single write
    /// where 120ms produced the full burst — so this is not padding, it is the
    /// shorter of the two values that was actually seen to work, and it is not safe
    /// to trim without re-measuring.
    public static let defaultHold: Duration = .milliseconds(120)

    // Effects, injected so the ordering rules below are testable without SkyLight,
    // without a real app, and without taking anyone's focus.
    let available: @Sendable () -> Bool
    let secureInputActive: @Sendable () -> Bool
    let runningPID: @Sendable () -> pid_t?
    let isActive: @Sendable () -> Bool
    let isHidden: @Sendable () -> Bool
    let setHidden: @Sendable (Bool) -> Void
    /// Captures the current front process. Non-zero means it could not be read, and
    /// without it there is nothing to restore, so the activation must not happen.
    let saveFront: @Sendable () -> Int32
    let makeFront: @Sendable (pid_t) -> Int32
    let restoreFront: @Sendable () -> Int32
    let sleep: @Sendable (Duration) async -> Void

    public init(
        available: @escaping @Sendable () -> Bool = Live.available,
        secureInputActive: @escaping @Sendable () -> Bool = Live.secureInputActive,
        runningPID: @escaping @Sendable () -> pid_t?,
        isActive: @escaping @Sendable () -> Bool,
        isHidden: @escaping @Sendable () -> Bool,
        setHidden: @escaping @Sendable (Bool) -> Void,
        saveFront: @escaping @Sendable () -> Int32 = Live.saveFront,
        makeFront: @escaping @Sendable (pid_t) -> Int32 = Live.makeFront,
        restoreFront: @escaping @Sendable () -> Int32 = Live.restoreFront,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.available = available
        self.secureInputActive = secureInputActive
        self.runningPID = runningPID
        self.isActive = isActive
        self.isHidden = isHidden
        self.setHidden = setHidden
        self.saveFront = saveFront
        self.makeFront = makeFront
        self.restoreFront = restoreFront
        self.sleep = sleep
    }

    /// Run one activation. Never throws; every failure is an `Outcome`.
    ///
    /// The guard order is the contract. Each guard is above the front change
    /// because each one describes a state in which taking the front would be wrong
    /// rather than merely useless, and a guard below it would mean the user's focus
    /// had already moved by the time we decided not to move it.
    public func run(hold: Duration = defaultHold) async -> Outcome {
        guard available() else { return .unavailable }
        // A password field owns the keyboard. Even 120ms of it going somewhere else
        // is unacceptable, and macOS will not report what was typed, so this can
        // never be made safe by checking afterwards.
        guard !secureInputActive() else { return .refusedSecureInput }
        guard let pid = runningPID() else { return .notRunning }
        // Above the front change because swapping the front process to the app that
        // already holds it is pure cost: it cannot fire the activation the caller
        // wants, and it still spends the hold.
        guard !isActive() else { return .alreadyActive }

        // Read before anything moves: activating an app unhides it, and on one of
        // the two trials that side effect appeared and on the other it did not — so
        // restoring this is not optional, it is covering a coin flip.
        let wasHidden = isHidden()
        let saveCode = saveFront()
        guard saveCode == 0 else { return .failed(code: saveCode) }

        let code = makeFront(pid)
        guard code == 0 else { return .failed(code: code) }

        // From here on the front process has moved, so every exit restores it.
        defer {
            _ = restoreFront()
            if wasHidden { setHidden(true) }
        }
        await sleep(hold)
        return .activated(heldFor: hold)
    }

    // MARK: - Live effects

    /// The SkyLight side, resolved once and shared. A `final class` rather than
    /// free functions because the saved front process has to live somewhere between
    /// ``saveFront`` and ``restoreFront``.
    public final class Live: @unchecked Sendable {
        public static let shared = Live()

        /// An 8-byte `ProcessSerialNumber`. Declared here rather than imported so
        /// that nothing in this file depends on the deprecated Carbon struct.
        private struct PSN { var hi: UInt32 = 0; var lo: UInt32 = 0 }

        private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
        private typealias GetFrontFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
        private typealias SetFrontFn = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32

        /// Front the process without bringing any of its windows forward.
        private static let kCPSNoWindows: UInt32 = 0x400

        private let lock = NSLock()
        private var saved: PSN?

        private let getProcessForPID: GetProcessForPIDFn?
        private let getFront: GetFrontFn?
        private let setFront: SetFrontFn?

        private init() {
            let sky = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
            func sym<T>(_ name: String, _ handle: UnsafeMutableRawPointer?) -> T? {
                guard let handle, let p = dlsym(handle, name) else { return nil }
                return unsafeBitCast(p, to: T.self)
            }
            getFront = sym("_SLPSGetFrontProcess", sky)
            setFront = sym("_SLPSSetFrontProcessWithOptions", sky)
            getProcessForPID = sym("GetProcessForPID", dlopen(nil, RTLD_LAZY))
            if getFront == nil || setFront == nil || getProcessForPID == nil {
                Log.scan.notice("skylight symbols missing — silent activation unavailable")
            }
        }

        /// Whether all three symbols resolved. Checked by the caller before anything
        /// else, so a macOS that drops them costs a refusal rather than a crash.
        public static let available: @Sendable () -> Bool = { shared.resolved }
        var resolved: Bool { getFront != nil && setFront != nil && getProcessForPID != nil }

        /// Whether a password field (or anything else) has taken secure input.
        /// Public Carbon API, unlike everything else in this class.
        public static let secureInputActive: @Sendable () -> Bool = { IsSecureEventInputEnabled() }

        public static let saveFront: @Sendable () -> Int32 = { shared.saveFrontProcess() }
        public static let makeFront: @Sendable (pid_t) -> Int32 = { shared.makeFrontProcess($0) }
        public static let restoreFront: @Sendable () -> Int32 = { shared.restoreFrontProcess() }

        func saveFrontProcess() -> Int32 {
            guard let getFront else { return -1 }
            var psn = PSN()
            let code = getFront(&psn)
            if code == 0 {
                lock.lock(); saved = psn; lock.unlock()
            }
            return code
        }

        func makeFrontProcess(_ pid: pid_t) -> Int32 {
            guard let getProcessForPID, let setFront else { return -1 }
            var psn = PSN()
            let code = getProcessForPID(pid, &psn)
            guard code == 0 else { return code }
            return setFront(&psn, 0, Self.kCPSNoWindows)
        }

        func restoreFrontProcess() -> Int32 {
            guard let setFront else { return -1 }
            lock.lock(); let psn = saved; lock.unlock()
            guard var psn else { return -1 }
            return setFront(&psn, 0, Self.kCPSNoWindows)
        }
    }
}
