import Foundation
import DuoUpdaterCore

/// Three renderings of one sweep: the terminal (for a human running it by hand),
/// JSON (for the reconcile step that files issues), and Markdown (for the CI
/// artifact and the issue bodies themselves).
///
/// Every string reaching any of them was already scrubbed when the `Finding` was
/// constructed, so there is no formatting path that can leak a credential.
public enum Report {

    /// Days rendered for a human: "3 days", "1 day", "18 hours". Durations here
    /// are always shown alongside a sweep count, so this only has to be readable,
    /// not precise.
    static func duration(_ days: Double?) -> String {
        guard let days else { return "?" }
        if days < 1 {
            let hours = Int((days * 24).rounded())
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        let whole = Int(days.rounded())
        return "\(whole) day\(whole == 1 ? "" : "s")"
    }


    // MARK: - terminal

    static func text(
        _ findings: [Finding], elapsed: Int, baseline: Baseline, showSamples: Bool
    ) {
        for finding in findings where finding.status.isActionable {
            let streak = baseline.streak(finding.recipeID)
            let pending = finding.status == .broken && !baseline.isReportable(finding.recipeID)
            print("""

              \(finding.status.glyph) \(finding.status.rawValue.uppercased())  \(finding.recipeID)\
            \(pending ? "   (streak \(streak)/\(Baseline.actionableThreshold) — not yet reportable)" : "")
                  \(finding.registry.label) · \(finding.endpointHost)
            """)
            if let pattern = finding.pattern {
                print("      pattern   /\(pattern)/")
            }
            if let kind = finding.failureKind, let detail = finding.failureDetail {
                print("      failure   \(kind) — \(detail)")
            }
            if let version = finding.version {
                print("      resolved  \(version)")
            }
            for warning in finding.warnings
            where !warning.hasPrefix(Finding.machineNotePrefix) {
                print("      warning   \(warning)")
            }
            if showSamples, let sample = finding.bodySample {
                print("      ── body sample ──")
                for line in sample.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
                    print("      | \(line.prefix(160))")
                }
            }
        }

        // Notes ride on findings that are otherwise fine, so the loop above —
        // which prints only actionable statuses — would never show them. They
        // describe the machine doing the sweeping rather than the recipe, and a
        // reader who cannot see them is back to the silent fallback this exists
        // to end.
        let notes = findings.flatMap { finding in
            finding.warnings
                .filter { $0.hasPrefix(Finding.machineNotePrefix) }
                .map { (finding.recipeID, String($0.dropFirst(Finding.machineNotePrefix.count))) }
        }
        if !notes.isEmpty {
            print("\n  \u{24D8} NOTES (about this machine, not the recipe)")
            for (recipeID, note) in notes {
                print("      \(recipeID) — \(note)")
            }
        }

        let infra = findings.filter { $0.status == .infra }
        if !infra.isEmpty {
            print("\n  ~ INFRA (transient by default — reported once persistent)")
            for finding in infra {
                let streak = baseline.infraStreak(finding.recipeID)
                let days = baseline.infraElapsed(finding.recipeID).map { $0 / 86_400 }
                let note: String
                if baseline.isInfraReportable(finding.recipeID) {
                    note = "   ← unreachable \(Self.duration(days)) "
                        + "(\(streak) sweeps); treated as GONE"
                } else if streak > 1, let days {
                    note = "   (unreachable \(Self.duration(days)) of "
                        + "\(Self.duration(Baseline.infraWindow / 86_400)))"
                } else {
                    note = ""
                }
                print("      \(finding.recipeID) — \(finding.failureDetail ?? "?") "
                    + "(\(finding.attempts) attempt\(finding.attempts == 1 ? "" : "s"))\(note)")
            }
        }
        let skipped = findings.filter { $0.status == .skipped }
        if !skipped.isEmpty {
            print("\n  - SKIPPED")
            for finding in skipped {
                print("      \(finding.recipeID) — \(finding.failureDetail ?? "not applicable")")
            }
        }

        print("\n  ─────────────────────────────────────────────")
        for registry in Registry.allCases {
            let subset = findings.filter { $0.registry == registry }
            guard !subset.isEmpty else { continue }
            print("  \(registry.label.padding(toLength: 14, withPad: " ", startingAt: 0))"
                + summary(subset))
        }
        print("  total          \(summary(findings))      \(elapsed)s")
    }

    private static func summary(_ findings: [Finding]) -> String {
        let counts = Dictionary(grouping: findings, by: \.status).mapValues(\.count)
        func n(_ s: FindingStatus) -> Int { counts[s] ?? 0 }
        return "✓ \(n(.ok))  ⚠ \(n(.warn))  ✗ \(n(.broken))  ~ \(n(.infra))  - \(n(.skipped))"
    }

    // MARK: - machine readable

    public struct Document: Codable, Sendable {
        public let schemaVersion = 1
        public let generatedAt: Date
        public let findings: [Finding]
    }

    static func json(_ findings: [Finding], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = Document(generatedAt: Date(), findings: findings)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    /// One section per actionable finding, in the shape an issue body wants:
    /// what broke, where, what the pattern is, and the evidence to fix it.
    static func markdown(_ findings: [Finding], baseline: Baseline, to url: URL) throws {
        var out = "# Recipe verification — \(ISO8601DateFormatter().string(from: Date()))\n\n"
        out += "| | ✓ ok | ⚠ warn | ✗ broken | ~ infra | - skipped |\n"
        out += "|---|---|---|---|---|---|\n"
        for registry in Registry.allCases {
            let subset = findings.filter { $0.registry == registry }
            guard !subset.isEmpty else { continue }
            let counts = Dictionary(grouping: subset, by: \.status).mapValues(\.count)
            func n(_ s: FindingStatus) -> Int { counts[s] ?? 0 }
            out += "| \(registry.label) | \(n(.ok)) | \(n(.warn)) | \(n(.broken)) "
                + "| \(n(.infra)) | \(n(.skipped)) |\n"
        }

        // Persistently-unreachable endpoints belong in the artifact for the same
        // reason they belong in the tracker: by the time a host has been gone a
        // week, "infra" is a description of the cause, not a reason to stay quiet.
        let actionable = findings.filter {
            $0.status.isActionable
                || ($0.status == .infra && baseline.isInfraReportable($0.recipeID))
        }
        if actionable.isEmpty {
            out += "\nNothing actionable.\n"
        }
        for finding in actionable {
            out += "\n## \(finding.status.glyph) `\(finding.recipeID)`\n\n"
            out += "<!-- duo-verify-id: \(finding.recipeID) -->\n\n"
            out += "- **registry**: \(finding.registry.label)\n"
            out += "- **endpoint host**: `\(finding.endpointHost)`\n"
            if let pattern = finding.pattern {
                out += "- **pattern**: `\(pattern)`\n"
            }
            if let kind = finding.failureKind, let detail = finding.failureDetail {
                out += "- **failure**: `\(kind)` — \(detail)\n"
            }
            if let version = finding.version {
                out += "- **resolved**: `\(version)`\n"
            }
            if let previous = baseline.entries[finding.recipeID]?.lastGoodVersion {
                out += "- **last good**: `\(previous)`\n"
            }
            let streak = baseline.streak(finding.recipeID)
            if streak > 0 {
                out += "- **consecutive sweeps**: \(streak)\n"
            }
            let infraStreak = baseline.infraStreak(finding.recipeID)
            if infraStreak > 0 {
                out += "- **unreachable for**: "
                out += baseline.infraElapsed(finding.recipeID)
                    .map { Self.duration($0 / 86_400) } ?? "?"
                out += " (\(infraStreak) sweeps)"
                out += baseline.entries[finding.recipeID]?.infraSince
                    .map { " (since \(ISO8601DateFormatter().string(from: $0).prefix(10)))" } ?? ""
                out += "\n"
            }
            for warning in finding.warnings {
                out += "- ⚠ \(warning)\n"
            }
            if let sample = finding.bodySample {
                out += "\n<details><summary>Captured response (redacted, truncated)</summary>\n\n"
                out += "```\n\(sample)\n```\n\n</details>\n"
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(out.utf8).write(to: url, options: .atomic)
    }
}
