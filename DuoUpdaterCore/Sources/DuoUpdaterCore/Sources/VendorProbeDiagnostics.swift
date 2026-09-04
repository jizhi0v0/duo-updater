import Foundation

/// Why a vendor probe didn't produce a version.
///
/// `VendorProbeSource` never manufactures a false "update available": it reports
/// a version or it reports nothing. What it used to do on top of that was
/// degrade every failure to a bare `nil`, which is useless to anyone asking
/// *why* — a vendor rewriting their download page and the office wifi dropping
/// look identical from the outside.
///
/// These cases split that single `nil` back apart, so an automated sweep can
/// tell "this recipe needs a human" (`Classification.recipe`) from "try again
/// later" (`.infra`) from "this recipe doesn't apply here" (`.notApplicable`).
///
/// **`classification` is load-bearing in the shipping check path, not only in
/// sweeps.** `VendorProbeSource.latestVersion(for:)` returns nil for
/// `.notApplicable` and *throws* for everything else, and `UpdateChecker` turns
/// that throw into an `.error` row — a red "Failed" badge with a Retry button —
/// where the nil stays the silent "—" that means no source covers this app.
/// So adding a case here decides what a user sees: `.notApplicable` for a
/// condition this Mac can do nothing about (no device identity, no recipe for
/// this track), the other two for a check that genuinely failed and is worth
/// retrying. Picking `.recipe` for an expected refusal puts a permanent red row
/// on every affected machine.
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
    /// The pattern matched nothing, but the same pattern with its segment count
    /// made variable matches `wouldMatch`. That is a vendor changing how many
    /// dot-separated numbers their version has — the Zotero `9.0.6` -> `10.0`
    /// shape — and it says both what broke and what the answer is.
    case versionSegmentCountChanged(wouldMatch: String, sampleBytes: Int)
    /// A rule that identifies an installed copy's channel by looking up its exact
    /// release (`GitHubReleaseRule.installedTagPrefix`) can no longer do so: the
    /// tag endpoint is gone, or its answer no longer carries the release-state
    /// fields the decision reads.
    ///
    /// It gets its own case because the ordinary version probe on such a rule
    /// keeps passing while this is broken — the sweep would stay green while
    /// every real install of that app quietly dropped out of the list, which is
    /// exactly the shape `duo verify` exists to catch.
    case channelDiscoveryBroken(String)
    /// The endpoint answered with a success status and the vendor's own error
    /// envelope in the body — their outage, reported inside a 200. Recognised
    /// only for a recipe that declares the envelope's shape
    /// (`VendorProbeRecipe.transientBodyPattern`); without that declaration the
    /// same body is `versionPatternNoMatch`, i.e. an accusation against the
    /// recipe.
    ///
    /// Infra — but "infra" here means *retried, and not reported until it
    /// persists*, not "ignored": `duo verify` retries it within the sweep and
    /// `Baseline.isInfraReportable` still surfaces it once it has held for
    /// `infraWindow` (five days). A vendor that moved its payload out of the key
    /// the envelope pattern watches would therefore be late, not invisible.
    /// Usually the fetch has already spent its one retry on this body, but not
    /// always — see the note at the throw site in `VendorProbeSource`.
    case vendorErrorEnvelope(sampleBytes: Int)

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
        case .transport, .nonHTTPResponse, .vendorErrorEnvelope:
            return .infra
        case .httpStatus(let code):
            // 5xx and 429 are the vendor having a bad day; 4xx means the URL we
            // hold is wrong, which is a recipe problem.
            return (code >= 500 || code == 429) ? .infra : .recipe
        case .redirectMissingLocation, .malformedResolvedURL,
             .archiveExtractionFailed, .plistKeyMissing, .versionPatternNoMatch,
             .versionSegmentCountChanged, .channelDiscoveryBroken:
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
        case .versionSegmentCountChanged: return "versionSegmentCountChanged"
        case .vendorErrorEnvelope: return "vendorErrorEnvelope"
        case .channelDiscoveryBroken: return "channelDiscoveryBroken"
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
        case .channelDiscoveryBroken(let why): return why
        case .versionPatternNoMatch(let bytes): return "no match in \(bytes)-byte body"
        case .versionSegmentCountChanged(let would, let bytes):
            return "no match in \(bytes)-byte body, but the same pattern with a "
                + "variable segment count matches \(would) — the vendor changed "
                + "how many numbers are in the version"
        case .vendorErrorEnvelope(let bytes):
            // Says whose fault it is, because this text is what the user reads in
            // the failed-check banner and what `duo verify` puts in a report.
            return "the vendor answered with an error, not a version "
                + "(\(bytes)-byte body)"
        }
    }
}

/// A recipe that still reads a version but has quietly lost part of its job.
///
/// These are invisible without an explicit warning: the probe returns a perfectly
/// good version and silently drops back to detection-only, loses release metadata,
/// or installs without the checksum the recipe author wrote down. A half-broken
/// recipe reads as healthy.
public enum ProbeWarning: Sendable, Equatable {
    /// The recipe carries an install spec but the installer URL didn't resolve —
    /// one-click is dead even though detection still works.
    case installURLUnresolved
    /// The installer URL could not be resolved because the vendor answered with
    /// a 5xx/429 or the request failed outright — after retrying.
    ///
    /// Kept apart from `installURLUnresolved` because the two accuse different
    /// people. That one says the recipe is wrong and someone has to go fix it;
    /// this one says the vendor was having a bad minute. `td.telegram.org`
    /// intermittently 502s the HEAD that resolves Telegram's download, which made
    /// a healthy recipe file issues against itself. The same 5xx/429-is-not-our-
    /// fault rule already governs version probes (see `ProbeFailure.category`).
    case installURLTransient(status: Int?)
    /// The installer URL resolved to a well-formed URL that the vendor no longer
    /// serves — a 4xx that survived a `Range: bytes=0-0` GET retry.
    ///
    /// Deliberately NOT `installURLUnresolved`. That one means the recipe could
    /// not even BUILD a URL (a pattern stopped matching), and the fix is to go
    /// re-derive the pattern. This one means the pattern still works and the
    /// vendor moved or deleted the artifact, and the fix is to find where it
    /// went. Collapsing them would hand whoever picks up the issue the wrong
    /// starting point.
    ///
    /// Only the sweep raises this: resolving an install URL is on the same code
    /// path as an ordinary update check, and a check must not pay an extra
    /// request per app for a question only the nightly asks. See
    /// `VendorProbeSource.probeDiagnostic(_:checkingInstallURL:)`.
    case installURLNotFound(status: Int?, host: String?)
    /// `checksumPattern` is set but matched nothing, so the download would be
    /// installed without SHA-512 verification.
    case checksumPatternNoMatch
    /// `entryStartPattern` is set but slicing produced no winning entry, so every
    /// pattern on this recipe ran against the WHOLE body, first-match — exactly
    /// the pre-#76 behaviour the field exists to replace.
    ///
    /// The fallback itself is the right call: a possibly-stale answer beats no
    /// answer. What was wrong is that it left no trace. A recipe can revert to
    /// the bug it was written to fix and go on reporting a plausible, confident,
    /// wrong version — `duo verify`'s only history check is a version moving
    /// BACKWARDS, which a first-match revert only trips during the rare window
    /// where two release trains overlap (the same window that made #76 visible
    /// at all). Outside it the sweep stays green.
    ///
    /// Three runtime paths reach it, and none of them fails anything:
    ///  - the pattern doesn't compile (closed for authored recipes by
    ///    `entryStartPatternsInTheRegistryAreValidRegexes`, still reachable here),
    ///  - it matches fewer than two entries — the vendor reformatted the feed.
    ///    Android Studio's `\{"date":"` is a byte-exact bet on minified JSON with
    ///    `date` as the first key: 671 matches on the live feed 2026-08-27, zero
    ///    for `{ "date"`, so pretty-printing it is enough,
    ///  - no entry matches `versionPattern`, or the winning entry matches it more
    ///    than once and the self-containment guard declines it.
    case entryPatternNoMatch
    /// `displayVersionPattern` is set but matched nothing, so the row falls back
    /// to showing the raw build id.
    ///
    /// The same shape as `checksumPatternNoMatch`: a pattern the recipe author
    /// wrote down, found nothing, and nothing failed. It is worth a warning of
    /// its own because the display string is not always cosmetic — a
    /// version-templated `ChangelogRecipe` builds its URL out of it
    /// (`ChangelogRecipe.urlVersionToken`), so losing it turns the release notes
    /// into a 404 while the version itself keeps resolving.
    ///
    /// `duo verify` cannot see this on its own. It records
    /// `shortVersion ?? version`, so a lost display string makes the recorded
    /// value jump from `155.0b5` to `20260826090609` — an increase, and the only
    /// history check there is looks for a version moving BACKWARDS.
    case displayPatternNoMatch
    /// `publishedAtPattern` is set but matched nothing, so the release timeline
    /// loses its exact event and falls back to its estimated "≈" window, and
    /// `duo verify`'s age-gated phantom-update check is disabled — the same
    /// consequence as `publishedAtUnreadable`, reached a different way.
    ///
    /// The same shape as `checksumPatternNoMatch` / `entryPatternNoMatch` /
    /// `displayPatternNoMatch`: a pattern the recipe author wrote down, found
    /// nothing, and nothing failed — the version keeps resolving, so a sweep
    /// with no warnings check would call this recipe healthy.
    ///
    /// Deliberately NOT `publishedAtUnreadable`. That one means the pattern DID
    /// fire and `ReleaseDate` rejected the captured text at both tiers — there
    /// is a value to show and a date spelling to add support for. This one
    /// means the pattern never matched at all, so there is nothing captured to
    /// show; the fix is to go re-derive the pattern against the vendor's
    /// current response, same as `displayPatternNoMatch`. A recipe missing
    /// `publishedAtPattern` entirely stays quiet — that is the normal,
    /// supported "no publish time" shape and not a degradation of anything the
    /// recipe author declared.
    case publishedAtPatternNoMatch
    /// `publishedAtPattern` captured a value, but `ReleaseDate.publishedFields`
    /// could parse it as neither a `.minute`-precise time nor a bare `.day` —
    /// so it produced neither `publishedAt` nor `vendorDay`. The version
    /// remains usable, but the release timeline loses this release's event
    /// entirely and `duo verify`'s age-gated phantom-update check is disabled.
    /// Carry the captured value so the recipe author can see which date
    /// spelling needs support without reproducing a response that may already
    /// have moved.
    case publishedAtUnreadable(String)

    /// The part of a warning that varies, kept OUT of `kind` on purpose.
    ///
    /// `kind` is what the reconcile step keys a filed issue on, so anything that
    /// moves between sweeps must not live there. But a bare `installURLNotFound`
    /// is close to useless to whoever picks the issue up: it cannot tell a 404
    /// (the artifact moved — go find it) from a 403 (a WAF or a geo-block — the
    /// recipe is fine), which is exactly the distinction the SourceForge
    /// false-accusation turned on. And the finding's `endpointHost` names the
    /// VERSION endpoint, which for this warning answered perfectly — so the host
    /// that actually failed appeared nowhere at all.
    ///
    /// Status and host, not the full URL: both are stable for a given recipe,
    /// where a `versionTemplate` URL changes with every release and would churn
    /// the signature for no new information.
    public var detail: String? {
        switch self {
        case .installURLNotFound(let status, let host):
            let code = status.map { "HTTP \($0)" } ?? "no answer"
            return host.map { "\(code) from \($0)" } ?? code
        case .installURLTransient(let status):
            return status.map { "HTTP \($0)" }
        case .publishedAtUnreadable(let value):
            // Keep a stable prefix longer than Finding.signature's 40-character
            // window; the captured value can change every release without making
            // one persistent parser problem look like a new failure each sweep.
            let oneLine = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let captured = oneLine.count > 160
                ? String(oneLine.prefix(160)) + "…"
                : oneLine
            return "captured value did not parse: \(captured)"
        default:
            return nil
        }
    }

    /// `kind`, plus `detail` when there is one. What the sweep publishes.
    public var display: String {
        detail.map { "\(kind): \($0)" } ?? kind
    }

    public var kind: String {
        switch self {
        case .installURLUnresolved: return "installURLUnresolved"
        case .installURLTransient: return "installURLTransient"
        case .installURLNotFound: return "installURLNotFound"
        case .checksumPatternNoMatch: return "checksumPatternNoMatch"
        case .entryPatternNoMatch: return "entryPatternNoMatch"
        case .displayPatternNoMatch: return "displayPatternNoMatch"
        case .publishedAtPatternNoMatch: return "publishedAtPatternNoMatch"
        case .publishedAtUnreadable: return "publishedAtUnreadable"
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
    /// needs to see to fix a pattern. For a recipe with `entryStartPattern` set,
    /// this is the ONE winning entry `VendorProbeSource` scoped everything else
    /// to — not the whole fetched body — so it matches what the recipe actually
    /// resolved against, not just whatever fits in the first
    /// ``ProbeOutcome/maxSampleBytes`` of the feed.
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
    ///
    /// Pass `pattern` whenever the caller knows which expression failed. Head and
    /// tail are a reasonable guess for a 4 KB JSON feed and worthless for a 1.6 MB
    /// changelog page, where the interesting markup is neither at the start nor
    /// the end: a first attempt at this handed a model 4 KB of page furniture and
    /// got back, correctly, "the entire list is inside the elided region."
    public static func condense(_ text: String, limit: Int, pattern: String? = nil) -> String {
        let trimmed = stripBoilerplate(text)
        guard trimmed.utf8.count > limit else { return trimmed }
        let elided = trimmed.utf8.count - limit

        if let pattern, let window = windowAroundAnchor(in: trimmed, pattern: pattern, limit: limit) {
            return window
        }
        // No pattern, or none of its literal anchors survive in the body. The
        // second case is itself worth stating — it means the markup the recipe
        // was written against is gone entirely, not merely rearranged.
        let note = pattern == nil
            ? "\n…[\(elided) bytes elided]…\n"
            : "\n…[\(elided) bytes elided; none of the pattern's literal anchors "
                + "appear anywhere in the body]…\n"
        return String(trimmed.prefix(limit * 3 / 4)) + note + String(trimmed.suffix(limit / 4))
    }

    /// Centre the sample on the most distinctive literal the pattern expects to
    /// find. If `<li id="codex-` still exists somewhere in a megabyte of HTML,
    /// that neighbourhood is the only part worth reading.
    static func windowAroundAnchor(in text: String, pattern: String, limit: Int) -> String? {
        let anchors = literalAnchors(in: pattern)
        guard !anchors.isEmpty else { return nil }
        for anchor in anchors {
            guard let range = text.range(of: anchor) else { continue }
            let before = limit / 3
            let after = limit - before
            let start = text.index(range.lowerBound, offsetBy: -before, limitedBy: text.startIndex)
                ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: after, limitedBy: text.endIndex)
                ?? text.endIndex
            return "…[sample centred on the pattern's anchor '\(anchor)']…\n"
                + String(text[start..<end]) + "\n…[truncated]…"
        }
        return nil
    }

    /// The literal runs a regex requires verbatim, longest first — the parts a
    /// vendor's rewrite would have had to preserve for the pattern to still work.
    public static func literalAnchors(in pattern: String) -> [String] {
        var runs: [String] = []
        var current = ""
        var iterator = pattern.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if character == "\\" {
                // An escaped metacharacter is a literal; anything else ends the run.
                if let next = iterator.next() {
                    if "\\^$.|?*+()[]{}/-".contains(next) { current.append(next) }
                    else { runs.append(current); current = "" }
                }
                continue
            }
            if "^$.|?*+()[]{}".contains(character) {
                runs.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        runs.append(current)
        return runs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 6 }
            .sorted { $0.count > $1.count }
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
    /// Stable sweep key for this recipe. A `variant` (only set when one channel
    /// has several endpoints) is appended, so the extra recipe gets its own
    /// baseline entry and every existing recipe's key is untouched.
    var recipeID: String {
        let base = "vendor:\(bundleID):\(channel.rawValue)"
        return variant.map { "\(base):\($0)" } ?? base
    }
}
