import Foundation

/// Where a row's Cancel stands while its install runs — what the menu-bar
/// app's rows draw beside their progress, app and command-line tool alike.
public enum InstallCancelState: Sendable, Equatable {
    /// Queued or preparing: Cancel is live.
    case available
    /// Clicked, and the cancel was accepted: "Cancelling…" until the row
    /// settles.
    case cancelling
    /// In or past its commit point: Cancel is greyed out.
    case committing
    /// Clicked, but the install had passed its commit point by then — the row
    /// had not yet heard. Not an error: the install finishes.
    case tooLate

    /// The state after a click on Cancel was answered `answer`.
    ///
    /// Not found is one of two things. With the row still `claimed` for its
    /// install, a job that has not registered yet — a target "Update All"
    /// started whose task has not run — so the cancel waits for it, and the
    /// host stops it before it registers. Otherwise a job that already ended:
    /// nil, and the row settles by itself.
    public static func after(_ answer: InstallJobs.CancelResult, claimed: Bool = false) -> InstallCancelState? {
        switch answer {
        case .cancelled: return .cancelling
        case .tooLate: return .tooLate
        case .notFound: return claimed ? .cancelling : nil
        }
    }

    /// The state once the job moved to `phase`, from `self`: a commit greys a
    /// live Cancel and a commit that did not land brings it back — also after a
    /// click it refused, which the registry did not keep (a `mas install` that
    /// exited non-zero is retried, and a cancel before the retry is a cancel);
    /// a Cancel accepted keeps saying "Cancelling…".
    public func following(_ phase: InstallJobs.Phase?) -> InstallCancelState {
        switch (self, phase) {
        case (.available, .committing): return .committing
        case (.committing, .preparing), (.tooLate, .preparing): return .available
        default: return self
        }
    }
}
