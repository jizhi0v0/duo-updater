import Foundation
import DuoUpdaterCore

/// Which registry a finding came from. The three are checked the same way and
/// reported together, but they break differently and are fixed in different
/// files, so the report has to keep them apart.
public enum Registry: String, Codable, Sendable, CaseIterable {
    case vendor
    case github
    case changelog

    public var label: String {
        switch self {
        case .vendor: return "vendor probe"
        case .github: return "GitHub rule"
        case .changelog: return "changelog"
        }
    }
}

/// What a sweep decided about one recipe.
public enum FindingStatus: String, Codable, Sendable {
    /// Read a version, nothing suspicious.
    case ok
    /// Read a version, but something degraded — install spec dead, checksum
    /// pattern stale, the value itself suspicious, or it went backwards.
    case warn
    /// A human needs to look at this recipe.
    case broken
    /// Network or vendor trouble. Never worth filing.
    case infra
    /// Not attempted: credential-bearing, or the registry says it doesn't apply.
    case skipped

    public var glyph: String {
        switch self {
        case .ok: return "✓"
        case .warn: return "⚠"
        case .broken: return "✗"
        case .infra: return "~"
        case .skipped: return "-"
        }
    }

    /// Only these justify filing anything. `infra` explicitly does not: a sweep
    /// that opens issues for dropped connections trains you to ignore it.
    public var isActionable: Bool { self == .broken || self == .warn }
}

public struct Finding: Codable, Sendable {
    public let recipeID: String
    public let registry: Registry
    public let bundleID: String
    public let channel: String
    public let status: FindingStatus
    public let version: String?
    public let failureKind: String?
    public let failureDetail: String?
    public let warnings: [String]
    /// Host only — never a resolved URL, which can carry an identifier.
    public let endpointHost: String
    public let pattern: String?
    public let attempts: Int
    public let elapsedMs: Int
    /// Redacted and capped. Present only for actionable findings, since this is
    /// the one field that carries arbitrary vendor content.
    public let bodySample: String?

    /// Every string here is scrubbed at construction rather than at the point of
    /// output, so there is no path from a sweep to a report, an issue body or a
    /// model prompt that skips redaction.
    public init(        recipeID: String, registry: Registry, bundleID: String, channel: String,
        status: FindingStatus, version: String? = nil,
        failureKind: String? = nil, failureDetail: String? = nil,
        warnings: [String] = [], endpointHost: String, pattern: String? = nil,
        attempts: Int = 1, elapsedMs: Int = 0, bodySample: String? = nil
    ) {
        self.recipeID = recipeID
        self.registry = registry
        self.bundleID = bundleID
        self.channel = channel
        self.status = status
        self.version = version
        self.failureKind = failureKind
        self.failureDetail = failureDetail.map { Redactor.text($0) }
        self.warnings = warnings.map { Redactor.text($0) }
        self.endpointHost = endpointHost
        self.pattern = pattern
        self.attempts = attempts
        self.elapsedMs = elapsedMs
        // Condense before redacting: the changelog path hands over a whole raw
        // HTML page, and a report full of `<link rel="preload">` is a report
        // nobody can act on.
        self.bodySample = status.isActionable
            ? bodySample.map {
                Redactor.text(ResponseSample.condense($0, limit: ProbeOutcome.maxSampleBytes))
            }
            : nil
    }
}
