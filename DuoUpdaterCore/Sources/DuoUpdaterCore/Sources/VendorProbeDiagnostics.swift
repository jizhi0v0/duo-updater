import Foundation

/// Why a vendor probe didn't produce a version.
///
/// `VendorProbeSource` is deliberately best-effort: every failure degrades to
/// `nil` so a broken recipe can never manufacture a false "update available."
/// That is right for the running app and useless for anyone asking *why* — a
/// vendor rewriting their download page and the office wifi dropping look
/// identical from the outside.
///
/// These cases split that single `nil` back apart, so an automated sweep can
/// tell "this recipe needs a human" (`Classification.recipe`) from "try again
/// later" (`.infra`) from "this recipe doesn't apply here" (`.notApplicable`).
/// Nothing in the shipping check path branches on them; they exist so failure is
/// attributable.
public enum ProbeFailure: Error, Sendable, Equatable {
    /// Toolbox-managed, channel gate refused, or no recipe for this bundle id.
    case notApplicable(String)
    /// `URLError` and friends — DNS, TLS, timeout, connection lost.
    case transport(urlErrorCode: Int, String)
    /// The response wasn't HTTP at all (file:// or a mangled proxy response).
    case nonHTTPResponse
    /// Fetched fine, wrong status for this recipe's mode.
    case httpStatus(Int)
    /// A no-follow redirect recipe got a 3xx with no `Location` header.
    case redirectMissingLocation
    /// The resolved location/final URL couldn't be parsed.
    case malformedResolvedURL(String)
    /// `.zipEntryPlist`: the archive downloaded but `unzip` couldn't produce the
    /// entry (vendor changed the stub installer's layout).
    case archiveExtractionFailed(String)
    /// `.zipEntryPlist`: the entry parsed as a plist but lacks the key.
    case plistKeyMissing(entry: String, key: String)
    /// **The signature failure of a broken recipe**: the endpoint answered, the
    /// body arrived, and `versionPattern` matched nothing in it.
    case versionPatternNoMatch(sampleBytes: Int)

    /// What a sweep should *do* about this failure.
    public enum Classification: String, Sendable {
        /// A human needs to look at the recipe.
        case recipe
        /// Transient. Retry; never file an issue.
        case infra
        /// Expected — this recipe simply doesn't cover this input.
        case notApplicable
    }

    public var classification: Classification {
        switch self {
        case .notApplicable:
            return .notApplicable
        case .transport, .nonHTTPResponse:
            return .infra
        case .httpStatus(let code):
            // 5xx and 429 are the vendor having a bad day; 4xx means the URL we
            // hold is wrong, which is a recipe problem.
            return (code >= 500 || code == 429) ? .infra : .recipe
        case .redirectMissingLocation, .malformedResolvedURL,
             .archiveExtractionFailed, .plistKeyMissing, .versionPatternNoMatch:
            return .recipe
        }
    }

    /// Short stable token for reports and issue titles.
    public var kind: String {
        switch self {
        case .notApplicable: return "notApplicable"
        case .transport: return "transport"
        case .nonHTTPResponse: return "nonHTTPResponse"
        case .httpStatus(let code): return "httpStatus\(code)"
        case .redirectMissingLocation: return "redirectMissingLocation"
        case .malformedResolvedURL: return "malformedResolvedURL"
        case .archiveExtractionFailed: return "archiveExtractionFailed"
        case .plistKeyMissing: return "plistKeyMissing"
        case .versionPatternNoMatch: return "versionPatternNoMatch"
        }
    }

    public var detail: String {
        switch self {
        case .notApplicable(let why): return why
        case .transport(let code, let message): return "URLError \(code): \(message)"
        case .nonHTTPResponse: return "response was not HTTPURLResponse"
        case .httpStatus(let code): return "HTTP \(code)"
        case .redirectMissingLocation: return "3xx with no Location header"
        case .malformedResolvedURL(let raw): return "cannot parse URL: \(raw)"
        case .archiveExtractionFailed(let why): return why
        case .plistKeyMissing(let entry, let key): return "\(entry) has no key '\(key)'"
        case .versionPatternNoMatch(let bytes): return "no match in \(bytes)-byte body"
        }
    }
}

/// A recipe that still reads a version but has quietly lost part of its job.
///
/// Both of these are invisible today: the probe returns a perfectly good version
/// and silently drops back to detection-only, or installs without the checksum
/// the recipe author wrote down. A half-broken recipe reads as healthy.
public enum ProbeWarning: Sendable, Equatable {
    /// The recipe carries an install spec but the installer URL didn't resolve —
    /// one-click is dead even though detection still works.
    case installURLUnresolved
    /// `checksumPattern` is set but matched nothing, so the download would be
    /// installed without SHA-512 verification.
    case checksumPatternNoMatch

    public var kind: String {
        switch self {
        case .installURLUnresolved: return "installURLUnresolved"
        case .checksumPatternNoMatch: return "checksumPatternNoMatch"
        }
    }
}

/// Everything one probe run learned, including the parts `latestVersion(for:)`
/// throws away. Produced by `VendorProbeSource.probeDiagnostic(_:)`.
public struct ProbeOutcome: Sendable {
    /// Stable sweep key: `vendor:<bundleID>:<channel>`.
    public let recipeID: String
    public let bundleID: String
    public let channel: ReleaseChannel
    /// Non-nil exactly when the shipping code path would have answered.
    public let remote: RemoteVersion?
    /// Non-nil exactly when `remote` is nil.
    public let failure: ProbeFailure?
    /// Non-empty only when `remote` is non-nil — degradations, not failures.
    public let warnings: [ProbeWarning]
    public let httpStatus: Int?
    /// The text the version pattern was run against, capped at
    /// ``ProbeOutcome/maxSampleBytes``. This is what a human (or a triage step)
    /// needs to see to fix a pattern.
    public let bodySample: String?
    public let elapsedMs: Int

    public static let maxSampleBytes = 4096

    public var succeeded: Bool { remote != nil }

    public init(
        recipeID: String, bundleID: String, channel: ReleaseChannel,
        remote: RemoteVersion?, failure: ProbeFailure?, warnings: [ProbeWarning] = [],
        httpStatus: Int? = nil, bodySample: String? = nil, elapsedMs: Int = 0
    ) {
        self.recipeID = recipeID
        self.bundleID = bundleID
        self.channel = channel
        self.remote = remote
        self.failure = failure
        self.warnings = warnings
        self.httpStatus = httpStatus
        self.bodySample = bodySample
        self.elapsedMs = elapsedMs
    }

    static func sample(_ text: String) -> String {
        ResponseSample.condense(text, limit: maxSampleBytes)
    }
}

/// Reduce a fetched response to the part a human — or a triage step — can
/// actually use to repair a broken pattern.
///
/// Naive truncation fails badly on the modern web. The first attempt kept the
/// leading 3 KB, which on a Next.js marketing page is 3 KB of
/// `<link rel="preload">` tags: the report was technically showing the response
/// and telling you nothing. Two rules fix it.
public enum ResponseSample {

    /// Keep the head *and* the tail. Version feeds put the newest entry at
    /// either end — the registry has recipes that read the *last* match
    /// precisely because some vendors list ascending — so head-only truncation
    /// discards exactly the region a broken pattern needs.
    ///
    /// Before that, drop `<head>` and `<style>`, which are pure chrome. `<script>`
    /// is deliberately **kept**: several recipes read their version out of an
    /// inlined `__NEXT_DATA__` or channel JSON blob, so stripping scripts would
    /// delete the evidence for the very recipes hardest to debug.
    public static func condense(_ text: String, limit: Int) -> String {
        let trimmed = stripBoilerplate(text)
        guard trimmed.utf8.count > limit else { return trimmed }
        let head = String(trimmed.prefix(limit * 3 / 4))
        let tail = String(trimmed.suffix(limit / 4))
        return head + "\n…[\(trimmed.utf8.count - limit) bytes elided]…\n" + tail
    }

    static func stripBoilerplate(_ text: String) -> String {
        guard text.range(of: "<head", options: [.caseInsensitive]) != nil
                || text.range(of: "<style", options: [.caseInsensitive]) != nil
        else { return text }
        var out = text
        for pattern in [#"(?is)<head\b[^>]*>.*?</head>"#, #"(?is)<style\b[^>]*>.*?</style>"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            out = regex.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out
    }
}

public extension VendorProbeRecipe {
    /// Stable sweep key for this recipe.
    var recipeID: String { "vendor:\(bundleID):\(channel.rawValue)" }
}
