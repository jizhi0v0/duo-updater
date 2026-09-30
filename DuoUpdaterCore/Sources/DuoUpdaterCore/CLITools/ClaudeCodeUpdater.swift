import Foundation

/// Runs the one-click update a `ClaudeCodeStatus` offers — the vendor's own
/// command, in the install's own place — and reports how it went.
///
/// SKELETON: the interface is fixed; the body is to be written.
public struct ClaudeCodeUpdater: Sendable {

    public enum Outcome: Sendable, Equatable {
        /// The command exited 0. `version` is what the install reads as afterwards
        /// (re-scanned), or nil when it could not be read.
        case updated(version: String?)
        /// Something else started updating it between the check and the click;
        /// nothing was run.
        case busy(ClaudeCodeActivity.Busy)
        /// The status offers no one-click (`oneClick == nil`); nothing was run.
        case notOffered
        /// The command ran and failed. `message` is its last meaningful output
        /// line, for the row; `output` the whole log, for the detail pane.
        case failed(message: String, output: String)
    }

    public init() {}

    /// - Parameter progress: each new line of the command's output, as it arrives.
    public func update(
        _ status: ClaudeCodeStatus,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> Outcome {
        .notOffered
    }
}
