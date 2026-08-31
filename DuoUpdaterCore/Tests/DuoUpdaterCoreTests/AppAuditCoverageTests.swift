import Testing
import Foundation
@testable import DuoUpdaterCore

/// Every app audit carries a 覆盖矩阵 — a per-channel table saying which of the
/// five sources answers for that app, and whether it is wired for one-click.
/// This asserts that table against the registry it describes.
///
/// **Why this cannot be a script.** The obvious version greps
/// `bundleID: "…"` out of `VendorProbeRecipe.swift`, and it is wrong: a good
/// number of recipes are built by factory functions (`workBuddyRecipe(bundleID:
/// host:…)`, and others like it) whose call sites a regex looking for
/// `VendorProbeRecipe(` never sees. Measured 2026-08-30, that shortcut reported
/// 24 audits as disagreeing with the registry; every one was the parser missing
/// a factory-built recipe or misreading the table, and zero were real. Asking
/// `VendorProbeRegistry.recipes` — the compiled array the app itself resolves
/// against — is the only reading that cannot drift from what ships.
///
/// The matrix is parsed rather than the prose because it is the one part of an
/// audit with a fixed shape. Everything else in these documents is reasoning,
/// and reasoning is what a human re-reads when they work on that app.
struct AppAuditCoverageTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .deletingLastPathComponent()   // repo root

    /// What one audit's matrix claims about the VendorProbe column.
    private struct Claim {
        let file: String
        let bundleKey: String       // filename, which is the bundle id with dots as dashes
        let hasProbe: Bool
        let hasOneClick: Bool
    }

    /// A bundle id in the form the audit filenames use: lowercased, dots to dashes.
    private static func key(_ bundleID: String) -> String {
        bundleID.replacingOccurrences(of: ".", with: "-").lowercased()
    }

    /// Read the VendorProbe column out of an audit's 覆盖矩阵.
    ///
    /// Returns nil when the document has no matrix (or no VendorProbe column),
    /// which is a shape this test has nothing to say about rather than a failure.
    private static func parseMatrix(_ text: String, file: String) -> Claim? {
        let lines = text.components(separatedBy: .newlines)
        // A table HEADER, not merely a row mentioning VendorProbe: the line after
        // a header is always the `|---|---|` separator. Without that test,
        // `issue-111-…md` — which is prose, not an audit — matched on a data row
        // reading "**VendorProbeRegistry** (`orbStackRecipe(…)`)" and got parsed
        // as if it were a coverage matrix.
        func isSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("|") && t.allSatisfy { "|-: \t".contains($0) }
        }
        guard let headerIndex = lines.indices.first(where: { i in
            lines[i].hasPrefix("|") && lines[i].contains("VendorProbe")
                && i + 1 < lines.count && isSeparator(lines[i + 1])
        }) else { return nil }

        // Split the raw line, not a trimmed one: the header's first cell is empty
        // (it labels the channel column) and trimming would shift every index.
        let header = lines[headerIndex].components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let column = header.firstIndex(where: { $0.contains("VendorProbe") })
        else { return nil }

        var cells: [String] = []
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("|") else { break }
            // The `|---|---|` separator row.
            if trimmed.allSatisfy({ "|-: \t".contains($0) }) { continue }
            let row = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard column < row.count else { continue }
            cells.append(row[column])
        }
        guard !cells.isEmpty else { return nil }

        return Claim(
            file: file,
            bundleKey: (file as NSString).deletingPathExtension.lowercased(),
            hasProbe: cells.contains { $0.contains("✓") },
            // "✓ 一键" is the established way the matrices mark it; a bare ✓ means
            // detection only. Both forms appear across the registry today.
            hasOneClick: cells.contains { $0.contains("✓") && $0.contains("一键") })
    }

    private static func auditClaims() throws -> [Claim] {
        let dir = repoRoot.appendingPathComponent("docs/app-audits")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
            .sorted()
        return try names.compactMap { name in
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            return parseMatrix(text, file: name)
        }
    }

    /// The audits are the reference; if this stops finding them the test is
    /// passing vacuously and would never fail again.
    @Test func theMatricesAreActuallyBeingRead() throws {
        let claims = try Self.auditClaims()
        #expect(
            claims.count > 60,
            Comment(rawValue: "only \(claims.count) audits parsed — did the matrix format change?"))
    }

    @Test func vendorProbeColumnMatchesTheRegistry() throws {
        var probe: [String: Bool] = [:]   // bundle key -> any recipe has an install spec
        for recipe in VendorProbeRegistry.recipes {
            let k = Self.key(recipe.bundleID)
            probe[k] = (probe[k] ?? false) || (recipe.install != nil)
        }

        var wrong: [String] = []
        for claim in try Self.auditClaims() {
            let registered = probe[claim.bundleKey]
            if claim.hasProbe && registered == nil {
                wrong.append("\(claim.file): matrix says VendorProbe ✓, registry has no recipe")
            }
            if !claim.hasProbe && registered != nil {
                wrong.append("\(claim.file): registry has a recipe the matrix does not mark ✓")
            }
            if let registered, claim.hasProbe, claim.hasOneClick, !registered {
                wrong.append("\(claim.file): matrix says 一键, recipe carries no install spec")
            }
            // The mirror of the line above — a recipe that HAS an install spec
            // whose matrix does not mark 一键 — is deliberately not asserted, and
            // the reason is granularity, not backlog. One-click is a PER-CHANNEL
            // fact: Warp wires it for stable and leaves preview/dev detection-only,
            // and several multi-channel apps are the same. This check reads the
            // registry at file granularity ("does any recipe for this bundle id
            // carry an install spec"), so turning the mirror on would force a 一键
            // mark onto rows that do not have one — making the table less true in
            // order to make a test pass.
            //
            // The five audits that genuinely contradicted the code here — Chrome,
            // Discord, Element, Firefox, Thunderbird each claiming "仅检测（设计
            // 如此）" while carrying an install spec — were stale text from before
            // `vendorInstallPolicy` replaced the old "never touch a self-updater"
            // rule, and were corrected on 2026-08-30.
        }
        #expect(
            wrong.isEmpty,
            Comment(rawValue: "app audits disagree with the registry:\n"
                + wrong.joined(separator: "\n")))
    }

    /// Keep generic Sparkle audits in their own index section. Several docs-only
    /// additions were accidentally appended to the preceding GitHub section;
    /// their `— S` marker was correct, but the grouping made the maintained index
    /// claim the opposite source at a glance.
    @Test func genericSparkleIndexRowsStayInTheSparkleSection() throws {
        let readme = Self.repoRoot.appendingPathComponent("docs/app-audits/README.md")
        let lines = try String(contentsOf: readme, encoding: .utf8)
            .components(separatedBy: .newlines)
        var section = ""
        var misplaced: [String] = []
        for (offset, line) in lines.enumerated() {
            if line.hasPrefix("## ") { section = String(line.dropFirst(3)) }
            if line.hasPrefix("- ["), line.contains("` — S"),
               section != "Sparkle-covered (auto-detected, no custom recipe)" {
                misplaced.append("line \(offset + 1) in section '\(section)': \(line)")
            }
        }
        #expect(
            misplaced.isEmpty,
            Comment(rawValue: "generic Sparkle audits are outside the Sparkle section:\n"
                + misplaced.joined(separator: "\n")))
    }

}
