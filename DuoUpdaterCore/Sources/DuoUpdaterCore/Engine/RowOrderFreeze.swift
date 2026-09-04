import Foundation

/// When the row order may stop being frozen, and what to write down while it
/// cannot.
///
/// The other half of `RowOrder`: that decides the order, this decides when the
/// order is allowed to change. Split out for the reason the freeze's own logging
/// exists — **a freeze that failed to lift looks exactly like a freeze that never
/// engaged.** From outside, both are "the list stopped re-sorting", so a release
/// condition with one term missing produces a permanently frozen list and no
/// symptom that names itself.
public enum RowOrderFreeze {

    /// Why the order must stay frozen, or nil when it may be released.
    ///
    /// Answers *may the freeze lift*, not *is there a freeze*. The caller still
    /// owns its own `pinnedOrder.isEmpty` early return, and that one is
    /// load-bearing: without it a settle point would re-sort a list that was
    /// never frozen — the exact reordering freezing exists to prevent — and log
    /// a release that never happened. Now that the ladder lives here, that guard
    /// reads like part of this condition. It is not.
    ///
    /// The string is the log line, and it is part of the answer rather than a
    /// side effect: it is the only thing that distinguishes the two
    /// indistinguishable states above in a live-log session, so which condition
    /// is reported is worth pinning too.
    ///
    /// - Parameters:
    ///   - installCount: rows with an install in flight.
    ///   - isInstallingAll: whether a batch install is running.
    ///   - relaunchCount: rows being relaunched.
    ///   - justUpdatedCount: rows still showing the just-updated confirmation.
    public static func holdReason(
        installCount: Int,
        isInstallingAll: Bool,
        relaunchCount: Int,
        justUpdatedCount: Int
    ) -> String? {
        // Order matters only for which reason is reported; any one of them holds
        // the freeze. Reported most-specific-first, matching what a reader
        // watching the log would want to see named.
        if installCount > 0 { return "installing (\(installCount))" }
        if isInstallingAll { return "batch install" }
        if relaunchCount > 0 { return "relaunching (\(relaunchCount))" }
        if justUpdatedCount > 0 { return "just-updated confirmation" }
        return nil
    }
}

/// How an install-progress tick is folded into the stage a row is showing.
///
/// Two rules, both of which fail quietly. Resurrecting a stage for a row whose
/// install is over re-shows a phantom row AND wedges the re-entrancy guard, which
/// keys on the stage being absent; and a download that reports every fraction
/// re-renders every row dozens of times a second, because the stage table
/// invalidates as a whole.
public enum InstallProgressCoalescing {

    /// - Parameters:
    ///   - current: the stage the row is showing, or nil when no install is in
    ///     flight for it.
    ///   - incoming: the stage the callback is reporting.
    /// - Returns: the stage to store, or nil to ignore the tick.
    public static func fold(
        current: InstallStage?, incoming: InstallStage
    ) -> InstallStage? {
        // Progress callbacks dispatch un-awaited onto the main actor, so a late
        // tick can land after the install finished and cleared the entry. Every
        // real stage is preceded by a direct assignment, so nil here means the
        // install is over — and resurrecting it would re-show a phantom row and
        // wedge the re-entrancy guard, which tests exactly this nil.
        guard current != nil else { return nil }
        if case .downloading(let fraction) = incoming,
           case .downloading(let previous)? = current,
           Int(fraction * 100) == Int(previous * 100) {
            // Same whole percent — nothing the user can see changed. A
            // `URLSession` download fires this dozens of times a second and the
            // table invalidates as a whole, so writing it re-renders every row.
            return nil
        }
        return incoming
    }
}
