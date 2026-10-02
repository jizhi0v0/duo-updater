import Foundation

/// SKELETON — replaced by the uv tool integration.
public struct UvToolProvider: CLIToolProvider {
    public var kind: CLIToolKind { .uvTool }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .uvTool, statuses: [], context: .uvTool)
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
