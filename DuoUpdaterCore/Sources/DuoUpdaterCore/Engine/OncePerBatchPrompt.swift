import Foundation

/// A permission dialog an install failure raises, shown at most once for the
/// runs of one "Update All".
///
/// A batch's parallel installs fail together on one stale permission, and three
/// identical dialogs would be worse than none. Since rows may be clicked while a
/// batch runs (#1503), "a batch is running" is no longer "this run is the
/// batch's": a row clicked by hand asks whatever the batch has already shown,
/// and does not use up the batch's one dialog either.
public struct OncePerBatchPrompt: Sendable, Equatable {
    private var shownInBatch = false

    public init() {}

    /// Whether this failure shows the dialog. `batchRun`: the failed install
    /// is one of the batch's own runs.
    public mutating func shouldPresent(batchRun: Bool) -> Bool {
        guard batchRun else { return true }
        guard !shownInBatch else { return false }
        shownInBatch = true
        return true
    }

    /// A batch starts or ends.
    public mutating func reset() { shownInBatch = false }
}
