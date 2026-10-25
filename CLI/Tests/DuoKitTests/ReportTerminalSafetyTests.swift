import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo verify`'s terminal report prints strings a vendor's endpoint supplies: the
/// version it resolved, its error text, a sample of its body. None of them may
/// reach the terminal with an escape sequence in them.
///
/// stdout is redirected to a file for the call, so the suite is serialized and the
/// assertions name the payloads rather than "no escape at all".
@Suite(.serialized) struct ReportTerminalSafetyTests {

    private static func printed(_ findings: [Finding], showSamples: Bool) throws -> String {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-report-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        fflush(stdout)
        let saved = dup(STDOUT_FILENO)
        let fd = open(file.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        #expect(fd >= 0)
        dup2(fd, STDOUT_FILENO)
        close(fd)
        Report.text(findings, elapsed: 1, baseline: Baseline(), showSamples: showSamples)
        fflush(stdout)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static let clipboard = "\u{1B}]52;c;ZXZpbA==\u{07}"
    private static let retitle = "\u{1B}]0;pwned\u{07}"
    private static let cursor = "\u{1B}[2J\u{1B}[1;1H"

    /// Mutation: print `finding.version`, `failureDetail`, `warnings` or the sample
    /// line raw again; the matching assertion goes red.
    @Test func whatTheVendorSuppliedIsPrintedWithoutEscapes() throws {
        let finding = Finding(
            recipeID: "demo.broken", registry: .vendor, bundleID: "com.example.demo", channel: "stable",
            status: .broken, version: "1.2.3\(Self.clipboard)",
            failureKind: "noMatch", failureDetail: "no match\(Self.retitle)\nforged  line",
            warnings: ["slow\(Self.cursor)"], endpointHost: "example.com", pattern: "v(\\d+)",
            bodySample: "<html>\(Self.clipboard)version 1.2.3\n\(Self.cursor)\u{9B}31mred</html>")
        let out = try Self.printed([finding], showSamples: true)

        #expect(out.contains("resolved  1.2.3\n"))
        #expect(out.contains("failure   noMatch — no matchforged  line\n"))
        #expect(out.contains("warning   slow\n"))
        #expect(out.contains("version 1.2.3"))
        for payload in [Self.clipboard, Self.retitle, Self.cursor, "\u{9B}", "\u{1B}]", "\u{1B}["] {
            #expect(!out.contains(payload), "\(payload.debugDescription) reached the terminal")
        }
    }

    /// The INFRA and SKIPPED sections print `failureDetail` too.
    @Test func theInfraAndSkippedLinesAreCleanToo() throws {
        let infra = Finding(
            recipeID: "demo.infra", registry: .vendor, bundleID: "b", channel: "stable",
            status: .infra, failureDetail: "timed out\(Self.clipboard)", endpointHost: "example.com")
        let skipped = Finding(
            recipeID: "demo.skipped", registry: .vendor, bundleID: "b", channel: "stable",
            status: .skipped, failureDetail: "n/a\(Self.retitle)", endpointHost: "example.com")
        let out = try Self.printed([infra, skipped], showSamples: false)
        #expect(out.contains("demo.infra — timed out"))
        #expect(out.contains("demo.skipped — n/a"))
        #expect(!out.contains(Self.clipboard) && !out.contains(Self.retitle))
    }
}
