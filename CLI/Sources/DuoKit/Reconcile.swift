import Foundation
import DuoUpdaterCore

// Turn a sweep into GitHub issues — one per broken recipe, closed automatically
// when it heals.
//
// The decision half is a pure function over (finding, baseline entry) so it can
// be tested exhaustively, and the `gh` half is a thin executor. That split is
// not ceremony: the single most likely way this system fails is not by missing a
// breakage but by generating so much noise that its issues get muted. Every rule
// below exists to keep the volume proportional to the news.

/// What reconciliation decided to do about one recipe.
public enum IssueAction: Equatable, Sendable {
    /// Nothing to do, with the reason (for the dry-run log).
    case none(String)
    case create(title: String, body: String)
    case comment(issue: Int, body: String)
    case close(issue: Int, comment: String)
    case reopen(issue: Int, comment: String)

    public var isWrite: Bool {
        if case .none = self { return false }
        return true
    }
}

public enum Reconcile {

    /// Comment on a still-broken issue only every Nth sweep. A daily job that
    /// comments daily is a daily notification saying nothing new.
    public static let commentEverySweeps = 7

    /// A recipe that broke again within this window reopens its old issue rather
    /// than opening a second one about the same thing.
    public static let reopenWindowDays = 14

    /// Never open more than this many issues in one sweep. If a run wants more,
    /// something systemic happened — a captive portal, a DNS outage — and the
    /// right output is one issue about that, not eighty about vendors.
    public static let maxNewIssuesPerSweep = 10

    /// Label carried on every issue this system opens, so they can be found and
    /// bulk-managed independently of the baseline file.
    public static let label = "recipe-broken"

    // MARK: - the decision

    public static func decide(
        _ finding: Finding, entry: Baseline.Entry, reportable: Bool,
        suggestion: TriageSuggestion? = nil, now: Date = Date()
    ) -> IssueAction {
        // Skipped means we didn't look — there is nothing to say either way.
        guard finding.status != .skipped else {
            return .none("skipped — never reported")
        }

        // Unreachable is *usually* nobody's fault and files nothing. But a host
        // that is unreachable on every sweep for the better part of a week has
        // been retired, and a retired endpoint kills a recipe just as dead as a
        // pattern that stopped matching. Filing at that point is the difference
        // between the sweep noticing a vendor shutting a host down and never
        // noticing it at all.
        if finding.status == .infra {
            guard entry.consecutiveInfra >= Baseline.infraThreshold else {
                return .none(
                    "infra — unreachable \(entry.consecutiveInfra)/"
                        + "\(Baseline.infraThreshold) sweeps, still assuming the network")
            }
            guard let issue = entry.issueNumber else {
                return .create(
                    title: unreachableTitle(for: finding, entry: entry),
                    body: unreachableBody(for: finding, entry: entry, now: now))
            }
            if let closedAt = entry.closedAt {
                let days = now.timeIntervalSince(closedAt) / 86_400
                guard days <= Double(reopenWindowDays) else {
                    return .create(
                        title: unreachableTitle(for: finding, entry: entry),
                        body: unreachableBody(for: finding, entry: entry, now: now))
                }
                return .reopen(
                    issue: issue,
                    comment: "The endpoint went unreachable again on \(Self.day(now)).\n\n"
                        + unreachableBody(for: finding, entry: entry, now: now))
            }
            // An issue is already open — either this same outage, or a parse
            // failure from before the host went away. Either way the only news
            // is that it is still down, so it goes through the same nudge limit
            // as everything else. No signature comparison: a dead host has no
            // shape to change, and transport errors flap between "no route" and
            // "TLS failed" for reasons that mean nothing.
            guard entry.sweepsSinceComment >= commentEverySweeps else {
                return .none(
                    "unreachable and already open (\(entry.sweepsSinceComment)/"
                        + "\(commentEverySweeps) sweeps since last comment)")
            }
            return .comment(
                issue: issue,
                body: "`\(finding.endpointHost)` is still unreachable as of "
                    + "\(Self.day(now)) — \(entry.consecutiveInfra) consecutive sweeps"
                    + (entry.infraSince.map { ", since \(Self.day($0))" } ?? "") + ".")
        }

        if finding.status == .ok {
            guard let issue = entry.issueNumber, entry.closedAt == nil else {
                return .none("healthy, nothing open")
            }
            let recovered = finding.version.map { " Now resolving `\($0)`." } ?? ""
            return .close(
                issue: issue,
                comment: "Self-healed: this recipe verified clean on "
                    + "\(Self.day(now)).\(recovered)\n\nReopened automatically if it "
                    + "breaks again within \(reopenWindowDays) days.")
        }

        // Actionable (broken or degraded) from here on.
        guard reportable else {
            return .none(
                "actionable but streak \(entry.consecutiveActionable)/"
                    + "\(Baseline.actionableThreshold) — one bad sweep is not news")
        }

        guard let issue = entry.issueNumber else {
            return .create(title: title(for: finding), body: body(for: finding, entry: entry, suggestion: suggestion))
        }

        // A closed issue coming back: reopen rather than duplicate, but only
        // while it's still recognisably the same episode.
        if let closedAt = entry.closedAt {
            let days = now.timeIntervalSince(closedAt) / 86_400
            guard days <= Double(reopenWindowDays) else {
                return .create(
                    title: title(for: finding), body: body(for: finding, entry: entry, suggestion: suggestion))
            }
            return .reopen(
                issue: issue,
                comment: "Broke again on \(Self.day(now)), \(Int(days)) day(s) after it "
                    + "healed.\n\n\(body(for: finding, entry: entry, suggestion: suggestion))")
        }

        // Open issue, still broken. Speak up only if something changed, or if
        // enough sweeps have passed that a nudge is warranted.
        if entry.lastSignature != finding.signature {
            return .comment(
                issue: issue,
                body: "The failure changed shape on \(Self.day(now)) — was "
                    + "`\(entry.lastSignature ?? "unknown")`, now "
                    + "`\(finding.signature)`.\n\n\(body(for: finding, entry: entry, suggestion: suggestion))")
        }
        // A suggestion the issue doesn't have yet is genuinely new information,
        // and `triagedSignature` means it arrives exactly once per distinct
        // failure rather than every sweep.
        if let suggestion, suggestion.signature == finding.signature,
           entry.triagedSignature != finding.signature {
            return .comment(
                issue: issue,
                body: "An automated analysis of the captured response is available.\n\n"
                    + suggestionBlock(suggestion))
        }
        guard entry.sweepsSinceComment >= commentEverySweeps else {
            return .none(
                "already open, unchanged (\(entry.sweepsSinceComment)/"
                    + "\(commentEverySweeps) sweeps since last comment)")
        }
        return .comment(
            issue: issue,
            body: "Still failing the same way after \(entry.consecutiveActionable) "
                + "consecutive sweeps, as of \(Self.day(now)).")
    }

    // MARK: - issue text

    static func title(for finding: Finding) -> String {
        let what = finding.status == .broken ? "Recipe broken" : "Recipe degraded"
        return "\(what): \(finding.bundleID) (\(finding.registry.label)) — \(reason(for: finding))"
    }

    /// Deliberately a different headline from `title(for:)`. "Recipe broken"
    /// sends someone to read a regex; the fix here is almost never in the
    /// pattern, it's that the endpoint has to be replaced.
    static func unreachableTitle(for finding: Finding, entry: Baseline.Entry) -> String {
        "Endpoint unreachable: \(finding.bundleID) (\(finding.registry.label)) — "
            + "`\(finding.endpointHost)` on \(entry.consecutiveInfra) consecutive sweeps"
    }

    static func unreachableBody(
        for finding: Finding, entry: Baseline.Entry, now: Date
    ) -> String {
        var out = "<!-- duo-verify-id: \(finding.recipeID) -->\n\n"
        out += "`\(finding.endpointHost)` has not answered on "
        out += "**\(entry.consecutiveInfra) consecutive sweeps**"
        out += entry.infraSince.map { ", starting \(Self.day($0))" } ?? ""
        out += ". A single unreachable sweep is suppressed as ordinary network trouble; "
        out += "this many in a row is not the network. The usual cause is that the vendor "
        out += "retired the host.\n\n"
        out += "| | |\n|---|---|\n"
        out += "| recipe | `\(finding.recipeID)` |\n"
        out += "| registry | \(finding.registry.label) |\n"
        out += "| endpoint host | `\(finding.endpointHost)` |\n"
        if let kind = finding.failureKind, let detail = finding.failureDetail {
            out += "| last error | `\(kind)` — \(detail) |\n"
        }
        if let previous = entry.lastGoodVersion {
            out += "| last version read | `\(previous)`"
            out += entry.lastGoodAt.map { " on \(Self.day($0))" } ?? ""
            out += " |\n"
        }
        out += "\nFirst thing to check — whether the name still resolves at all, which "
        out += "separates a retired host from a reachable one that is merely refusing us:\n\n"
        out += "```bash\ndig +short \(finding.endpointHost) @1.1.1.1\n```\n\n"
        out += "If that comes back empty, the endpoint is gone and the recipe needs a new "
        out += "source or needs deleting — it cannot be fixed in place.\n\n"
        out += "Reproduce the sweep's own view:\n\n```bash\nswift run --package-path CLI duo verify "
        out += "--\(finding.registry.rawValue) --only \(finding.bundleID)\n```\n"
        return out
    }

    /// A short, readable cause for the title. Not `signature`: that is keyed for
    /// stable comparison across sweeps and truncates mid-word, which reads as
    /// sloppy in a title you'll scan a list of.
    static func reason(for finding: Finding) -> String {
        if let kind = finding.failureKind { return kind }
        guard let first = finding.warnings.first else { return "degraded" }
        // Warnings are written as "<claim> — <explanation>"; the claim is the
        // headline, and it is already a complete thought.
        let claim = first.components(separatedBy: " — ").first ?? first
        guard claim.count > 70 else { return claim }
        let cut = claim.prefix(70)
        let atWord = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        return atWord + "…"
    }

    /// The body carries the marker comment so an issue can be re-associated with
    /// its recipe even if the baseline file is lost or rewritten.
    static func body(
        for finding: Finding, entry: Baseline.Entry,
        suggestion: TriageSuggestion? = nil
    ) -> String {
        var out = "<!-- duo-verify-id: \(finding.recipeID) -->\n\n"
        out += "Found by the scheduled `duo verify` sweep. "
        out += "The version check and the app both keep working in the cases marked "
        out += "*degraded* — that is what makes these invisible without this job.\n\n"
        out += "| | |\n|---|---|\n"
        out += "| recipe | `\(finding.recipeID)` |\n"
        out += "| registry | \(finding.registry.label) |\n"
        out += "| endpoint host | `\(finding.endpointHost)` |\n"
        if let pattern = finding.pattern {
            out += "| pattern | `\(pattern)` |\n"
        }
        if let kind = finding.failureKind, let detail = finding.failureDetail {
            out += "| failure | `\(kind)` — \(detail) |\n"
        }
        if let version = finding.version {
            out += "| resolved | `\(version)` |\n"
        }
        if let previous = entry.lastGoodVersion {
            out += "| last good | `\(previous)` |\n"
        }
        out += "| consecutive sweeps | \(entry.consecutiveActionable) |\n"

        if !finding.warnings.isEmpty {
            out += "\n**Warnings**\n\n"
            for warning in finding.warnings { out += "- \(warning)\n" }
        }
        if let sample = finding.bodySample {
            out += "\n<details><summary>Captured response (redacted, truncated)</summary>\n\n"
            out += "```\n\(sample)\n```\n\n</details>\n"
        }
        // After the captured response, so a reader has seen the evidence before
        // the interpretation of it.
        if let suggestion, suggestion.signature == finding.signature {
            out += "\n" + suggestionBlock(suggestion)
        }
        out += "\nReproduce locally:\n\n```bash\nswift run --package-path CLI duo verify "
        out += "--\(finding.registry.rawValue) --only \(finding.bundleID) --samples\n```\n"
        return out
    }

    /// The model's answer, with the one checkable fact first and the prose
    /// folded away behind it.
    ///
    /// The order is the point. `verificationLine` is produced by re-running the
    /// proposal through the same extractor the app uses, so it is true or false
    /// on its own terms; the diagnosis is a guess about someone else's website.
    /// Putting the guess first would invite applying it unread.
    static func suggestionBlock(_ suggestion: TriageSuggestion) -> String {
        var out = "### Automated analysis\n\n"
        out += suggestion.verificationLine + "\n\n"
        out += "<details><summary>Unverified suggestion — do not apply without testing"
        out += " (model: `\(suggestion.model)`, self-reported confidence "
        out += "\(String(format: "%.2f", suggestion.confidence)))</summary>\n\n"
        out += "\(suggestion.diagnosis)\n\n"
        if let pattern = suggestion.proposedVersionPattern {
            out += "Proposed pattern:\n\n```\n\(pattern)\n```\n\n"
        }
        out += "Produced by a model with no tools, in an empty directory, from the "
        out += "captured response above. That response is third-party content and may "
        out += "be hostile; nothing here has been applied to any file.\n\n</details>\n"
        return out
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    // MARK: - execution

    public struct Options: Sendable {
        public var reportPath: URL
        public var baselinePath: URL
        /// Optional: suggestions from `duo triage`, embedded into issue bodies.
        public var triagePath: URL?
        public var dryRun: Bool
        public init(
            reportPath: URL, baselinePath: URL, triagePath: URL? = nil, dryRun: Bool
        ) {
            self.reportPath = reportPath
            self.baselinePath = baselinePath
            self.triagePath = triagePath
            self.dryRun = dryRun
        }
    }

    public static func run(_ options: Options) -> Int32 {
        guard let data = try? Data(options.reportPath) else {
            die("cannot read report at \(options.reportPath.path)", code: 2)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(Report.Document.self, from: data) else {
            die("cannot parse report at \(options.reportPath.path)", code: 2)
        }
        var baseline = Baseline.load(from: options.baselinePath)
        let suggestions = loadSuggestions(options.triagePath)

        // Check the one external dependency before deciding anything. Without
        // this the run dies at the first `gh issue create` with a bare exit 127
        // — after a full 46-second sweep, in a step whose name says "File and
        // close issues", pointing at everything except the actual cause.
        if !options.dryRun, let missing = GitHub.unavailableReason() {
            die("""
                cannot reach the GitHub CLI: \(missing)

                `duo reconcile` shells out to `gh` so it authenticates the same way
                you do locally and picks up GITHUB_TOKEN on a runner. A CI runner's
                PATH is not a login shell's — on this machine Homebrew's prefix has
                to be added explicitly.
                """, code: 2)
        }

        // Decide everything first, then apply — so the circuit breaker sees the
        // whole picture before a single issue is opened.
        var decisions: [(Finding, IssueAction)] = []
        for finding in document.findings {
            let entry = baseline.entries[finding.recipeID] ?? Baseline.Entry()
            decisions.append((finding, decide(
                finding, entry: entry,
                reportable: baseline.isReportable(finding.recipeID),
                suggestion: suggestions[finding.recipeID])))
        }

        let creations = decisions.filter { if case .create = $0.1 { return true } else { return false } }
        if creations.count > maxNewIssuesPerSweep {
            print("""

              ⛔︎ \(creations.count) recipes would open issues this sweep, over the \
            cap of \(maxNewIssuesPerSweep).
                 That is not \(creations.count) vendors changing their sites on the same day —
                 it is an infrastructure failure wearing a costume. Filing one summary
                 issue instead; re-run once the network is known good.
            """)
            return applySummary(creations.map(\.0), options: options)
        }

        var failures = 0
        for (finding, action) in decisions {
            guard action.isWrite else {
                // Infra reasons print too once the streak has started: the whole
                // point is that a host quietly going away should be visible in
                // the log on the way to being visible in the tracker.
                let entry = baseline.entries[finding.recipeID] ?? Baseline.Entry()
                let worthSaying = finding.status.isActionable
                    || (finding.status == .infra && entry.consecutiveInfra > 1)
                if case .none(let reason) = action, worthSaying {
                    print("  · \(finding.recipeID): \(reason)")
                }
                continue
            }
            if options.dryRun {
                print("  [dry-run] \(finding.recipeID): \(describe(action))")
                continue
            }
            do {
                try apply(action, to: &baseline, recipeID: finding.recipeID)
                if let suggestion = suggestions[finding.recipeID],
                   suggestion.signature == finding.signature {
                    baseline.entries[finding.recipeID]?.triagedSignature = suggestion.signature
                }
                print("  ✓ \(finding.recipeID): \(describe(action))")
            } catch {
                FileHandle.standardError.write(
                    Data("  ✗ \(finding.recipeID): \(error)\n".utf8))
                failures += 1
            }
        }

        if !options.dryRun {
            baseline.updatedAt = Date()
            try? baseline.save(to: options.baselinePath)
        }
        return failures == 0 ? 0 : 1
    }

    /// Suggestions are optional throughout: triage may have been skipped, may
    /// have been rate-limited, or may have failed. None of that should stop a
    /// breakage being filed.
    static func loadSuggestions(_ path: URL?) -> [String: TriageSuggestion] {
        guard let path, let data = try? Data(contentsOf: path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(TriageDocument.self, from: data) else {
            FileHandle.standardError.write(
                Data("⚠︎ could not read triage suggestions at \(path.path); continuing without them\n".utf8))
            return [:]
        }
        return Dictionary(
            document.suggestions.map { ($0.recipeID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private static func describe(_ action: IssueAction) -> String {
        switch action {
        case .none(let reason): return "no action (\(reason))"
        case .create(let title, _): return "create — \(title)"
        case .comment(let issue, _): return "comment on #\(issue)"
        case .close(let issue, _): return "close #\(issue)"
        case .reopen(let issue, _): return "reopen #\(issue)"
        }
    }

    private static func apply(
        _ action: IssueAction, to baseline: inout Baseline, recipeID: String
    ) throws {
        switch action {
        case .none:
            return
        case .create(let title, let body):
            let number = try GitHub.createIssue(title: title, body: body, label: label)
            baseline.entries[recipeID]?.issueNumber = number
            baseline.entries[recipeID]?.closedAt = nil
            baseline.entries[recipeID]?.sweepsSinceComment = 0
        case .comment(let issue, let body):
            try GitHub.comment(issue: issue, body: body)
            baseline.entries[recipeID]?.sweepsSinceComment = 0
        case .close(let issue, let comment):
            try GitHub.close(issue: issue, comment: comment)
            baseline.entries[recipeID]?.closedAt = Date()
        case .reopen(let issue, let comment):
            try GitHub.reopen(issue: issue, comment: comment)
            baseline.entries[recipeID]?.closedAt = nil
            baseline.entries[recipeID]?.sweepsSinceComment = 0
        }
    }

    private static func applySummary(_ findings: [Finding], options: Options) -> Int32 {
        let body = "<!-- duo-verify-id: sweep-anomaly -->\n\n"
            + "A single sweep found \(findings.count) recipes newly actionable, over the "
            + "cap of \(maxNewIssuesPerSweep). Individual issues were suppressed.\n\n"
            + findings.map { "- `\($0.recipeID)` — \($0.signature)" }.joined(separator: "\n")
            + "\n\nMost likely causes, in order: the runner lost DNS or sat behind a "
            + "captive portal; an outbound proxy started intercepting TLS; the machine "
            + "resumed from sleep mid-run.\n"
        if options.dryRun {
            print("  [dry-run] would open a sweep-anomaly summary issue")
            return 0
        }
        do {
            _ = try GitHub.createIssue(
                title: "Recipe sweep anomaly: \(findings.count) recipes actionable at once",
                body: body, label: label)
            return 0
        } catch {
            FileHandle.standardError.write(Data("could not file summary issue: \(error)\n".utf8))
            return 1
        }
    }
}

private extension Data {
    init(_ url: URL) throws { try self.init(contentsOf: url) }
}
