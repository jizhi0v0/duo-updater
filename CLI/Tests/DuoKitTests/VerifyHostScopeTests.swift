import Foundation
import Testing
@testable import DuoKit
import DuoUpdaterCore

@Suite struct VerifyHostScopeTests {
    private func recipe(_ requirement: VendorHostRequirement?) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.duoupdater.test.host-scope",
            url: URL(string: "https://unsupported-host.invalid/latest.json")!,
            mode: .responseBody, versionPattern: #""version":"([0-9.]+)""#,
            changelogURL: URL(string: "https://unsupported-host.invalid/notes"),
            hostRequirement: requirement)
    }

    @Test func supportedHostsIncludeNeutralAndUniversalRecipesAndOtherOSFloors() {
        for requirement in [
            nil,
            VendorHostRequirement(),
            VendorHostRequirement(architectures: [.arm64]),
            VendorHostRequirement(architectures: [.x86_64, .arm64]),
            VendorHostRequirement(minimumSystemVersion: "99.0", architectures: [.arm64]),
        ] as [VendorHostRequirement?] {
            #expect(Verify.unsupportedHostReason(for: recipe(requirement)) == nil)
        }
    }

    @Test func theVendorSweepSkipsAnIntelHostBeforeResolvingItsEndpoint() async throws {
        let intel = recipe(VendorHostRequirement(architectures: [.x86_64]))
        var options = VerifyOptions()
        options.infraRetries = 0
        let findings = await Verify.sweepVendor(
            [intel], options: options, installed: [:], collecting: Verify.ResolvedInstallURLs())
        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.recipeID == intel.recipeID)
        #expect(finding.status == .skipped)
        #expect(finding.failureDetail?.contains("Apple Silicon") == true)
        #expect(finding.version == nil)
        #expect(finding.warnings.isEmpty)
    }

    @Test func anUnsupportedHostsChangelogIsNotFetched() {
        let intel = recipe(VendorHostRequirement(architectures: [.x86_64]))
        let arm = recipe(VendorHostRequirement(architectures: [.arm64]))
        #expect(ChangelogLinkSweep.pages(of: [intel]).isEmpty)
        #expect(ChangelogLinkSweep.pages(of: [arm]) == [arm.changelogURL!])
    }

    @Test func theInstallSweepCanReportOnlySkippedRecipesWithoutDownloading() async throws {
        let intel = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "jan-nightly.ai.app"
                && $0.hostRequirement?.architectures == [.x86_64]
        })
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-verify-host-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = InstallVerifyOptions()
        options.only = [intel.recipeID]
        options.allowStaleBinary = true
        options.githubToken = "fixture-no-keychain-lookup"
        options.jsonPath = directory.appendingPathComponent("report.json")

        #expect(await InstallVerify.run(options) == 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(
            InstallVerify.Report.self, from: Data(contentsOf: options.jsonPath!))
        let item = try #require(report.items.first)
        #expect(report.items.count == 1)
        #expect(item.recipeID == intel.recipeID)
        #expect(item.status == .skipped)
        #expect(item.detail?.contains("Apple Silicon") == true)
        #expect(report.bytes == 0)
        #expect(item.version == nil)
    }

    @Test func aSkippedIntelFindingCannotReopenItsOldIssue() async throws {
        let intel = recipe(VendorHostRequirement(architectures: [.x86_64]))
        let findings = await Verify.sweepVendor(
            [intel], options: VerifyOptions(), installed: [:],
            collecting: Verify.ResolvedInstallURLs())
        let finding = try #require(findings.first)
        var entry = Baseline.Entry()
        entry.issueNumber = 1797
        entry.closedAt = Date()
        entry.consecutiveActionable = 40
        #expect(!Reconcile.decide(finding, entry: entry, reportable: true).isWrite)
    }
}
