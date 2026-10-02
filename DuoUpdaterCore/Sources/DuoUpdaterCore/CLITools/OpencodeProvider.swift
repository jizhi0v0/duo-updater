import Foundation

/// SKELETON — replaced by the opencode integration.
public struct OpencodeProvider: CLIToolProvider {
    public var kind: CLIToolKind { .opencode }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .opencode, statuses: [], context: .opencode(OpencodeSettings()))
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
