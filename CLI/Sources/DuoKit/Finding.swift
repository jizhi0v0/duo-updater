import Foundation
import DuoUpdaterCore

/// Which registry a finding came from. They are checked the same way and
/// reported together, but they break differently and are fixed in different
/// files, so the report has to keep them apart.
public enum Registry: String, Codable, Sendable, CaseIterable {
    case vendor
    case github
    case changelog
    /// `MacAppStoreSource` isn't a recipe — it has no per-app config to sweep,
    /// it asks Apple's lookup API whatever bundle id an installed app carries.
    /// This registry instead sweeps `MacAppStoreProbeRegistry`'s committed list
    /// of long-lived App Store apps, checking that the lookup `kind` and the
    /// product-page shapes `MacAppStoreSource` parses still look the way its
    /// code assumes — see `MacAppStoreProbeRegistry`'s doc comment.
    case appStore = "appstore"
    /// `SparkleFeedCatalog` isn't a recipe registry either — it holds
    /// ADDRESSES, handed to apps whose own bundle does not give us a usable
    /// one. Nothing on a schedule had ever fetched them (#324), and a feed that
    /// dies, moves or reshapes its items produces a nil out of
    /// `SparkleAppcastSource` that every caller renders as "up to date". See
    /// `FeedVerify.swift`.
    case feed

    public var label: String {
        switch self {
        case .vendor: return "vendor probe"
        case .github: return "GitHub rule"
        case .changelog: return "changelog"
        case .appStore: return "App Store probe"
        case .feed: return "Sparkle feed"
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
    /// HTTP requests the sweep actually spent on this recipe — the outer
    /// `infraRetries` probes plus any gateway retry inside them. A request count,
    /// not a probe count, so it cannot understate what an endpoint cost.
    public let attempts: Int
    /// How many of `attempts` were `URLSession.versionFeedData`'s single retry —
    /// on a 502/503/504, or on a 2xx whose body the recipe declares as the
    /// vendor's error envelope (`VendorProbeRecipe.transientBodyPattern`).
    /// Non-zero on an otherwise `ok` finding is the signal worth having: the
    /// endpoint flapped and recovered, which no other field records.
    ///
    /// The name outlived its one cause — kept so a `report.json` written before
    /// the second one existed still decodes, and because a reader who wants to
    /// know WHICH flap has the recipe id and the endpoint on the same line.
    ///
    /// Optional so a `report.json` written before this existed still decodes — nil
    /// means "not recorded", which is not the same claim as zero.
    public let gatewayRetries: Int?
    /// Entries the changelog sweep extracted from the page, when this finding
    /// came from one. Recorded because `version` alone cannot see the failure
    /// where an entry pattern's terminator stops matching: the first entry then
    /// swallows the rest of the document, the version still parses correctly
    /// off its heading, and the sweep goes green on a recipe that has collapsed
    /// to one entry carrying the whole page (#324, #393).
    ///
    /// Optional so a `report.json` written before this existed still decodes —
    /// nil means "not recorded", which is not the same claim as zero. Only the
    /// changelog sweep sets it; no other registry has entries to count.
    public let entryCount: Int?
    public let elapsedMs: Int
    /// Redacted and capped. Present only for actionable findings, since this is
    /// the one field that carries arbitrary vendor content.
    public let bodySample: String?

    /// Every string here is scrubbed at construction rather than at the point of
    /// output, so there is no path from a sweep to a report, an issue body or a
    /// model prompt that skips redaction.
    /// Warnings minus machine notes — the subset that may be published.
    ///
    /// A note names this machine's state (a file it could not read), and a
    /// GitHub issue about a vendor's recipe is exactly the wrong audience for
    /// it. `Report` prints the full set and `report.json` keeps it; everything
    /// that writes vendor-facing text uses this instead. See
    /// `Finding.machineNotePrefix`.
    public var publicWarnings: [String] {
        warnings.filter { !$0.hasPrefix(Finding.machineNotePrefix) }
    }

    public init(        recipeID: String, registry: Registry, bundleID: String, channel: String,
        status: FindingStatus, version: String? = nil,
        failureKind: String? = nil, failureDetail: String? = nil,
        warnings: [String] = [], endpointHost: String, pattern: String? = nil,
        attempts: Int = 1, gatewayRetries: Int? = nil,
        entryCount: Int? = nil, elapsedMs: Int = 0, bodySample: String? = nil
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
        self.gatewayRetries = gatewayRetries
        self.entryCount = entryCount
        self.elapsedMs = elapsedMs
        // Condense before redacting: the changelog path hands over a whole raw
        // HTML page, and a report full of `<link rel="preload">` is a report
        // nobody can act on.
        self.bodySample = status.isActionable
            ? bodySample.map {
                Redactor.text(ResponseSample.condense(
                    $0, limit: ProbeOutcome.maxSampleBytes, pattern: pattern))
            }
            : nil
    }
}
