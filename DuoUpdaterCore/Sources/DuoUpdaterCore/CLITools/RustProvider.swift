import Foundation

/// SKELETON — replaced by the rust integration.
public struct RustProvider: CLIToolProvider {
    public var kind: CLIToolKind { .rust }

    public init() {}

    public func scan() async -> [CLIToolSighting] { [] }

    public func check() async -> CLIToolReport {
        CLIToolReport(kind: .rust, statuses: [], context: .rust(RustupSettings()))
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
