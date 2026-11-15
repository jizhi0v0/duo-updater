import Foundation
import Testing
@testable import DuoKit

@Suite struct ReconcilePersistenceTests {

    @Test func runReturnsFailureWhenBaselineCannotBeSaved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-reconcile-persistence-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let reportURL = root.appendingPathComponent("report.json")
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("file, not a directory".utf8).write(to: blocker)
        try Report.json([Finding(
            recipeID: "vendor:com.example.healthy",
            registry: .vendor,
            bundleID: "com.example.healthy",
            channel: "-",
            status: .ok,
            endpointHost: "updates.example.com")], to: reportURL)

        let result = await Reconcile.run(.init(
            reportPath: reportURL,
            baselinePath: blocker.appendingPathComponent("baseline.json"),
            dryRun: false), githubUnavailableReason: { nil })

        #expect(result == 2)
    }
}
