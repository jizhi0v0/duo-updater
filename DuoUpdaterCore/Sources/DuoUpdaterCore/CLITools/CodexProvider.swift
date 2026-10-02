import Foundation

/// SKELETON — replaced by the Codex integration.
public struct CodexProvider: CLIToolProvider {
    public var kind: CLIToolKind { .codex }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .codex, statuses: [], context: .codex(CodexSettings()))
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
