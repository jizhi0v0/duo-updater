import Foundation

/// SKELETON — replaced by the npm integration.
public struct NpmProvider: CLIToolProvider {
    public var kind: CLIToolKind { .npm }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .npm, statuses: [], context: .npm)
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        .notOffered
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        throw CLIToolReleaseNotesError.noSections
    }
}
