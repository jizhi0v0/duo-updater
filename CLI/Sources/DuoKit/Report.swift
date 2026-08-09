import Foundation
import DuoUpdaterCore

/// Three renderings of one sweep: the terminal (for a human running it by hand),
/// JSON (for the reconcile step that files issues), and Markdown (for the CI
/// artifact and the issue bodies themselves).
///
/// Every string reaching any of them was already scrubbed when the `Finding` was
/// constructed, so there is no formatting path that can leak a credential.
public enum Report {

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
            for warning in finding.warnings {
                print("      warning   \(warning)")
            }
            if showSamples, let sample = finding.bodySample {
                print("      ── body sample ──")
                for line in sample.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
                    print("      | \(line.prefix(160))")
                }
            }
        }

        let infra = findings.filter { $0.status == .infra }
        if !infra.isEmpty {
            print("\n  ~ INFRA (not actionable, never reported)")
            for finding in infra {
                print("      \(finding.recipeID) — \(finding.failureDetail ?? "?") "
                    + "(\(finding.attempts) attempt\(finding.attempts == 1 ? "" : "s"))")
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

        let actionable = findings.filter(\.status.isActionable)
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
