import Foundation

/// SKELETON — replaced by the junie integration.
public struct JunieProvider: CLIToolProvider {
    public var kind: CLIToolKind { .junie }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .junie, statuses: [], context: .junie(JunieSettings()))
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
