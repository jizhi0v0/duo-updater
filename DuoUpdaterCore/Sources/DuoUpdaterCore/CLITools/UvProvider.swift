import Foundation

/// SKELETON — replaced by the uv integration.
public struct UvProvider: CLIToolProvider {
    public var kind: CLIToolKind { .uv }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .uv, statuses: [], context: .uv)
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
