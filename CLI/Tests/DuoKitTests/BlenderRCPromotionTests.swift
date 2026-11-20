import Testing
import DuoUpdaterCore
@testable import DuoKit

@Suite struct BlenderRCPromotionTests {
    private let stableID = "vendor:org.blenderfoundation.blender:stable"
    private let rcID = "vendor:org.blenderfoundation.blender:rc"

    private func blender(
        _ channel: ReleaseChannel, version: String?, status: FindingStatus = .ok,
        warnings: [String] = []
    ) -> Finding {
        Finding(
            recipeID: "vendor:org.blenderfoundation.blender:\(channel.rawValue)", registry: .vendor,
            bundleID: "org.blenderfoundation.blender", channel: channel.rawValue,
            status: status, version: version, warnings: warnings,
            endpointHost: channel == .stable ? "mirror.blender.org" : "builder.blender.org")
    }

    private func priorBaseline() -> Baseline {
        var baseline = Baseline()
        var rc = Baseline.Entry()
        rc.lastGoodVersion = "5.3.0"
        rc.consecutiveActionable = 7
        rc.issueNumber = 2107
        baseline.entries[rcID] = rc
        return baseline
    }

    @Test func promotedBlenderRCRebasesItsLastGoodVersion() throws {
        var baseline = priorBaseline()
        let stable = blender(.stable, version: "5.3.0")
        let findings = Verify.foldingBaselineComplaints(
            [blender(.rc, version: "5.2.5"), stable], into: &baseline)

        let rc = try #require(findings.first { $0.recipeID == rcID })
        #expect(rc.status == .ok)
        #expect(rc.publicWarnings.isEmpty)
        #expect(baseline.entries[rcID]?.lastGoodVersion == "5.2.5")
        #expect(baseline.entries[rcID]?.consecutiveActionable == 0)
        #expect(baseline.entries[rcID]?.issueNumber == 2107)

        // Publication of 5.3.0 says nothing about disappearance of 5.2.5.
        let next = Verify.foldingBaselineComplaints(
            [blender(.rc, version: "4.5.17"), stable], into: &baseline)
        #expect(next.first?.status == .warn)
        #expect(baseline.entries[rcID]?.lastGoodVersion == "5.2.5")
    }

    @Test func unconfirmedBlenderRCPromotionRetainsTheRegression() throws {
        let otherReports: [[Finding]] = [
            [],
            [blender(.stable, version: "5.3.1")],
            [blender(.stable, version: "5.3.0", status: .warn)],
            [blender(.stable, version: nil, status: .skipped)],
            [blender(.stable, version: "5.3.0", warnings: ["installURLTransient: HTTP 502"])],
        ]
        for reports in otherReports {
            var baseline = priorBaseline()
            let findings = Verify.foldingBaselineComplaints(
                reports + [blender(.rc, version: "4.5.17")], into: &baseline)
            let rc = try #require(findings.last)
            #expect(rc.status == .warn)
            #expect(rc.publicWarnings.contains { $0.contains("BACKWARDS") })
            #expect(baseline.entries[rcID]?.lastGoodVersion == "5.3.0")
        }
    }

    @Test func aRegressedStableReportCannotVerifyPromotion() {
        var baseline = priorBaseline()
        var stable = Baseline.Entry()
        stable.lastGoodVersion = "5.3.1"
        baseline.entries[stableID] = stable

        let findings = Verify.foldingBaselineComplaints(
            [blender(.rc, version: "4.5.17"), blender(.stable, version: "5.3.0")], into: &baseline)

        #expect(findings.map(\.status) == [.warn, .warn])
        #expect(baseline.entries[rcID]?.lastGoodVersion == "5.3.0")
        #expect(baseline.entries[stableID]?.lastGoodVersion == "5.3.1")
    }

    @Test func stablePublicationDoesNotExemptOtherBlenderChannels() {
        var baseline = priorBaseline()
        let previous = blender(.beta, version: "5.3.0")
        baseline.reconcile(previous)

        let findings = Verify.foldingBaselineComplaints(
            [blender(.stable, version: "5.3.0"), blender(.beta, version: "5.2.5")], into: &baseline)

        #expect(findings.last?.status == .warn)
        #expect(baseline.entries[previous.recipeID]?.lastGoodVersion == "5.3.0")
    }

    @Test func aDegradedCandidateDoesNotReplaceTheTrustedBaseline() throws {
        var baseline = priorBaseline()
        let candidate = blender(.rc, version: "5.2.5", status: .warn, warnings: ["installer unresolved"])

        let findings = Verify.foldingBaselineComplaints(
            [candidate, blender(.stable, version: "5.3.0")], into: &baseline)

        let rc = try #require(findings.first)
        #expect(rc.status == .warn)
        #expect(rc.publicWarnings.contains("installer unresolved"))
        #expect(rc.publicWarnings.contains { $0.contains("BACKWARDS") })
        #expect(baseline.entries[rcID]?.lastGoodVersion == "5.3.0")
    }
}
