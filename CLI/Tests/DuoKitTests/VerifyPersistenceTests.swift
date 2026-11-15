import Foundation
import Testing
@testable import DuoKit

struct VerifyPersistenceTests {
    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyPersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private var findings: [Finding] {
        [Finding(recipeID: "vendor:com.example.app:stable", registry: .vendor,
                 bundleID: "com.example.app", channel: "stable", status: .ok,
                 endpointHost: "example.com")]
    }

    @Test(arguments: ["json", "markdown", "baseline"])
    func aRequestedArtifactThatCannotBeWrittenFailsTheRun(artifact: String) throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = VerifyOptions()
        options.jsonPath = root.appendingPathComponent("report.json")
        options.markdownPath = root.appendingPathComponent("report.md")
        options.baselinePath = root.appendingPathComponent("baseline.json")
        // A directory is never a valid file destination, even for a privileged
        // test runner. Permission-bit fixtures would accidentally pass as root.
        switch artifact {
        case "json": options.jsonPath = root
        case "markdown": options.markdownPath = root
        default: options.baselinePath = root
        }
        #expect(throws: (any Error).self) {
            try Verify.writeArtifacts(findings, baseline: Baseline(), options: options)
        }
    }

    @Test func aFreshReportAndItsRequestedStateAreBothWritten() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = VerifyOptions()
        options.jsonPath = root.appendingPathComponent("report.json")
        options.markdownPath = root.appendingPathComponent("report.md")
        options.baselinePath = root.appendingPathComponent("baseline.json")
        try Verify.writeArtifacts(findings, baseline: Baseline(), options: options)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: options.jsonPath!))
            as? [String: Any]
        let rows = json?["findings"] as? [[String: Any]]
        #expect(rows?.first?["recipeID"] as? String == findings[0].recipeID)
        #expect(FileManager.default.fileExists(atPath: options.markdownPath!.path))
        #expect(FileManager.default.fileExists(atPath: options.baselinePath!.path))
    }
}
