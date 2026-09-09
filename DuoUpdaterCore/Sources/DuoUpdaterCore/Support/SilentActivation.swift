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
/// write-ahead log, and `lsof` sampling TestFlight's own sockets every 500ms). A
/// cold hidden launch was the positive control, so an empty row means "nothing
/// happened", not "the witness was blind":
///
/// | trigger | network | store | focus |
/// |---|---|---|---|
/// | cold hidden launch (control) | 6 connections | written | unchanged |
/// | **this, on a running instance** | **2 connections** | **written** | **unchanged** |
/// | `CGEventPostToPid` click | none | untouched | unchanged |
/// | `CGEventPostToPid` scroll | none | untouched | unchanged |
/// | AX `AXRaise` | none — refused | untouched | unchanged |
/// | AX `AXScrollDownByPage` | none — refused | untouched | unchanged |
///
/// ⚠️ **On those two AX rows.** Both actions were genuinely performed — verified
/// step by step, because the first reading of this had the error constant wrong and
/// a failure while *reading* an attribute would have meant the action was never
/// attempted at all. Copying `kAXWindows` succeeded (1 window), copying the action
/// names succeeded (`["AXRaise"]`), and only then did `AXUIElementPerformAction`
/// return **-25205, `kAXErrorAttributeUnsupported`** — for an action the element
/// itself advertises. Odd, but measured: the actions reach TestFlight, and
/// TestFlight refuses them.
///
/// The input-injection family therefore does not serve this, and the reason is the
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
/// **On permissions — what was measured and what is inferred.** *Measured*
/// 2026-09-10: run under `launchctl submit`, `AXIsProcessTrusted()` reported
/// `false` and the activation still succeeded and still made TestFlight go to the
/// network. *Inferred*: that this is because `launchctl submit` breaks the
/// responsibility chain which would otherwise lend the harness its parent's grant.
/// *Not measured*: the same run from the signed, hardened-runtime `duo` rather than
/// from an ad-hoc harness. So this is strong evidence that no Accessibility grant is
/// needed — the one way it beats `CGEventPostToPid`, which Apple documents as
/// requiring one — and not yet a guarantee.
public struct SilentActivation: Sendable {

    /// What one attempt did. Every case is something the caller may need to say out
    /// loud — a silent no-op would leave the user reading a stale version number
    /// believing it was just refreshed.
    public enum Outcome: Sendable, Equatable {
        /// The app was made active for `heldFor` and the previous state was restored.
        ///
        /// `heldFor` is the hold that was **requested**. Under `Task.cancel()` the
        /// production sleep returns early, so a cancelled run would report a hold
        /// longer than it took; the restore still happens, and the CLI never cancels.
        case activated(heldFor: Duration)
        /// SkyLight is not resolvable on this macOS. Not a failure to report as one.
        case unavailable
        /// Secure keyboard entry is on somewhere in this login session.
        case refusedSecureInput
        /// Nothing to activate — the app is not running, or has no pid.
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
        /// The activation happened, but putting the front process back did not —
        /// twice. Whatever the caller wanted from the activation is still valid; the
        /// user's focus is not where they left it, which is the worst thing this
        /// type can do and so is never folded into ``activated``.
        case frontNotRestored(code: Int32)
    }

    /// Whichever process was front before we moved it. Opaque on purpose: the only
    /// thing anyone may do with one is hand it back to `restoreFront`.
    public struct FrontProcess: Sendable, Equatable {
        let hi: UInt32
        let lo: UInt32
        public init(hi: UInt32, lo: UInt32) { self.hi = hi; self.lo = lo }
    }

    /// The result of reading the front process — the code is kept so a failure can
    /// be reported as the OSStatus it actually was.
    public enum FrontSnapshot: Sendable, Equatable {
        case saved(FrontProcess)
        case unreadable(code: Int32)
    }

    /// The outcome of one hop's worth of blocking work.
    public enum Step: Sendable, Equatable {
        /// The front has moved; here is what to put back and whether to re-hide.
        case fronted(previous: FrontProcess, wasHidden: Bool)
        /// Nothing is left moved, and this is the answer.
        case refused(Outcome)
        /// The post-hold hop: the restore's code, after up to one retry.
        case restored(code: Int32)
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
    /// The app's pid, or nil when there is nothing to activate.
    ///
    /// ⚠️ **nil, not -1.** `NSRunningApplication` documents that "applications
    /// without a pid return -1", that such an object "remains valid after the
    /// application exits", and that the pid "may change if it is automatically
    /// terminated" — which is exactly what happens to TestFlight. A wiring that
    /// forwards -1 makes ``Outcome/notRunning`` unreachable and turns a
    /// quit-during-the-race into `GetProcessForPID(-1)` failing: an error reported
    /// where a cold launch was the right answer.
    let runningPID: @Sendable () -> pid_t?
    let isActive: @Sendable () -> Bool
    let isHidden: @Sendable () -> Bool
    let setHidden: @Sendable (Bool) -> Void
    /// Captures the current front process. The snapshot is **returned to the
    /// caller** rather than parked in the shared `Live`: one process-wide slot is
    /// one save/restore pair, and two overlapping activations would interleave into
    /// it — A saves Claude, A fronts TestFlight, B saves *TestFlight*, and now
    /// neither restore puts the user back. Per-call state makes that
    /// unrepresentable rather than merely unlikely.
    let saveFront: @Sendable () -> FrontSnapshot
    let makeFront: @Sendable (pid_t) -> Int32
    let restoreFront: @Sendable (FrontProcess) -> Int32
    let sleep: @Sendable (Duration) async -> Void
    /// Hop for the blocking effects. Production sends them off the cooperative
    /// pool; tests run them inline so ordering stays observable.
    let offPool: @Sendable (@escaping @Sendable () -> Step) async -> Step

    public init(
        available: @escaping @Sendable () -> Bool = Live.available,
        secureInputActive: @escaping @Sendable () -> Bool = Live.secureInputActive,
        runningPID: @escaping @Sendable () -> pid_t?,
        isActive: @escaping @Sendable () -> Bool,
        isHidden: @escaping @Sendable () -> Bool,
        setHidden: @escaping @Sendable (Bool) -> Void,
        saveFront: @escaping @Sendable () -> FrontSnapshot = Live.saveFront,
        makeFront: @escaping @Sendable (pid_t) -> Int32 = Live.makeFront,
        restoreFront: @escaping @Sendable (FrontProcess) -> Int32 = Live.restoreFront,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        offPool: @escaping @Sendable (@escaping @Sendable () -> Step) async -> Step = Live.offPool
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
        self.offPool = offPool
    }

    /// Run one activation. Never throws; every failure is an `Outcome`.
    ///
    /// The blocking work runs in **two hops** off the cooperative pool, one either
    /// side of the hold, rather than one hop per call: the order inside each hop is
    /// load-bearing, and every extra hop is another chance to disturb it. All of it
    /// blocks — `dlopen`, XPC to LaunchServices, and synchronous Mach IPC to the
    /// WindowServer — and this repository has already lost an entire test process to
    /// blocking the cooperative pool (see ``offCooperativePool``).
    public func run(hold: Duration = defaultHold) async -> Outcome {
        let previousFront: FrontProcess
        let wasHidden: Bool
        switch await offPool({ self.takeFront() }) {
        case .refused(let outcome): return outcome
        case .fronted(let previous, let hidden):
            previousFront = previous
            wasHidden = hidden
        case .restored(let code):
            // `takeFront` never produces this; treat a hop that did as a failure
            // rather than falling through with an unset front to restore.
            return .failed(code: code)
        }

        await sleep(hold)

        // ⚠️ Process death during the hold skips this — a Ctrl-C in that 120ms
        // leaves the user's focus on the activated app. The window is small and the
        // damage is one focus change, so this is a documented limit rather than a
        // signal handler.
        guard case .restored(let restoreCode) =
                await offPool({ self.putFrontBack(previousFront, wasHidden: wasHidden) })
        else { return .failed(code: -1) }

        guard restoreCode == 0 else {
            Log.install.error(
                "silent activation could not restore the front process (code \(restoreCode, privacy: .public))")
            return .frontNotRestored(code: restoreCode)
        }
        return .activated(heldFor: hold)
    }

    /// Everything before the hold, in one hop.
    ///
    /// The guard order is the contract. Each guard is above the front change because
    /// each describes a state in which taking the front would be *wrong* rather than
    /// merely useless, and a guard below it would mean the user's focus had already
    /// moved by the time we decided not to move it.
    func takeFront() -> Step {
        guard available() else { return .refused(.unavailable) }
        // Secure keyboard entry is a **login-session** state, not "a password field
        // is focused right now": Terminal's Secure Keyboard Entry and some password
        // managers hold it for their whole lifetime. Refusing is still right — 120ms
        // of someone's typing going where they cannot see it is not recoverable —
        // but the caller's message must not promise it will clear on its own.
        guard !secureInputActive() else { return .refused(.refusedSecureInput) }
        guard let pid = runningPID() else { return .refused(.notRunning) }
        // Above the front change because swapping the front process to the app that
        // already holds it is pure cost: it cannot fire the activation the caller
        // wants, and it still spends the hold.
        guard !isActive() else { return .refused(.alreadyActive) }

        // Read before anything moves: activating an app unhides it, and on one of
        // the two trials that side effect appeared and on the other it did not — so
        // restoring this is not optional, it is covering a coin flip.
        let wasHidden = isHidden()

        // Nothing to put back afterwards means the front must not move at all: a
        // "restore" that lands somewhere the user did not choose is worse than never
        // having activated. Read **once** — asking twice and reporting the second
        // answer is how the first version of this returned a code the API never
        // produced, and no fixture with a constant stub could tell the two apart.
        switch saveFront() {
        case .unreadable(let code):
            return .refused(.failed(code: code))
        case .saved(let previous):
            let code = makeFront(pid)
            guard code == 0 else {
                // Put it back anyway. A non-zero return from a symbol with no
                // contract is not evidence that nothing moved, and that is the one
                // premise whose failure costs the user their focus with nothing
                // anywhere to say so.
                _ = restoreFront(previous)
                if wasHidden { setHidden(true) }
                return .refused(.failed(code: code))
            }
            return .fronted(previous: previous, wasHidden: wasHidden)
        }
    }

    /// Everything after the hold, in one hop.
    func putFrontBack(_ previous: FrontProcess, wasHidden: Bool) -> Step {
        var code = restoreFront(previous)
        if code != 0 {
            // One retry. Leaving someone's focus where they did not put it is the
            // worst thing this type can do, and re-asking costs nothing.
            code = restoreFront(previous)
        }
        if wasHidden { setHidden(true) }
        return .restored(code: code)
    }

    // MARK: - Live effects

    /// The SkyLight side, resolved once and shared.
    ///
    /// Deliberately **stateless**: it resolves symbols and calls them, and holds
    /// nothing between calls. The saved front process lives in the `run()` that
    /// saved it — see ``saveFront`` for why a shared slot was the wrong shape.
    public final class Live: Sendable {
        public static let shared = Live()

        /// An 8-byte `ProcessSerialNumber`. Declared here rather than imported so
        /// that nothing in this file depends on the deprecated Carbon struct.
        private struct PSN { var hi: UInt32 = 0; var lo: UInt32 = 0 }

        private typealias GetProcessForPIDFn =
            @convention(c) @Sendable (pid_t, UnsafeMutableRawPointer) -> Int32
        private typealias GetFrontFn = @convention(c) @Sendable (UnsafeMutableRawPointer) -> Int32
        private typealias SetFrontFn =
            @convention(c) @Sendable (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32

        /// Front the process without bringing any of its windows forward.
        private static let kCPSNoWindows: UInt32 = 0x400

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
            // Resolved out of the already-loaded image rather than by opening
            // HIServices: `import Carbon` above is what puts it there, so if that
            // import ever goes the feature degrades to `.unavailable` for good,
            // silently. `theLiveSymbolsResolveOnThisMac` is what notices.
            getProcessForPID = sym("GetProcessForPID", dlopen(nil, RTLD_LAZY))
            if getFront == nil || setFront == nil || getProcessForPID == nil {
                Log.install.notice("skylight symbols missing — silent activation unavailable")
            }
        }

        /// Whether all three symbols resolved. Checked by the caller before anything
        /// else, so a macOS that drops them costs a refusal rather than a crash.
        public static let available: @Sendable () -> Bool = { shared.resolved }
        var resolved: Bool { getFront != nil && setFront != nil && getProcessForPID != nil }

        /// Whether secure keyboard entry is on anywhere in this login session.
        /// Public Carbon API, unlike everything else in this class.
        public static let secureInputActive: @Sendable () -> Bool = { IsSecureEventInputEnabled() }

        public static let saveFront: @Sendable () -> FrontSnapshot = { shared.saveFrontProcess() }
        public static let makeFront: @Sendable (pid_t) -> Int32 = { shared.makeFrontProcess($0) }
        public static let restoreFront: @Sendable (FrontProcess) -> Int32 = { shared.restore($0) }

        /// The production hop. `offCooperativePool` is not cancellable, which is what
        /// this wants: a half-done front change must finish putting itself back
        /// rather than abandon someone's focus.
        public static let offPool: @Sendable (@escaping @Sendable () -> Step) async -> Step = { work in
            (try? await offCooperativePool { work() }) ?? .refused(.failed(code: -1))
        }

        func saveFrontProcess() -> FrontSnapshot {
            guard let getFront else { return .unreadable(code: -1) }
            var psn = PSN()
            let code = getFront(&psn)
            guard code == 0 else { return .unreadable(code: code) }
            return .saved(FrontProcess(hi: psn.hi, lo: psn.lo))
        }

        func makeFrontProcess(_ pid: pid_t) -> Int32 {
            guard let getProcessForPID, let setFront else { return -1 }
            var psn = PSN()
            let code = getProcessForPID(pid, &psn)
            guard code == 0 else { return code }
            return setFront(&psn, 0, Self.kCPSNoWindows)
        }

        func restore(_ front: FrontProcess) -> Int32 {
            guard let setFront else { return -1 }
            var psn = PSN(hi: front.hi, lo: front.lo)
            return setFront(&psn, 0, Self.kCPSNoWindows)
        }
    }
}
