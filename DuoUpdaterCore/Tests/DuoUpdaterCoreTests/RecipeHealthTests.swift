import Testing
import Foundation
@testable import DuoUpdaterCore

/// The recipe-health tracker that surfaces silently-broken detectors. Uses fresh
/// `RecipeHealth()` instances (not the shared singleton) so tests don't interfere.
struct RecipeHealthTests {

    @Test func pureSuccessIsHealthy() async {
        let health = RecipeHealth()
        await health.recordSuccess(id: "com.example.app", source: "Vendor")
        let snap = await health.snapshot()
        #expect(snap.count == 1)
        #expect(snap[0].isHealthy)
        #expect(await health.unhealthy().isEmpty)
    }

    @Test func pureMissIsUnhealthy() async {
        let health = RecipeHealth()
        await health.recordMiss(id: "owner/repo", source: "GitHub", detail: "no match")
        let unhealthy = await health.unhealthy()
        #expect(unhealthy.count == 1)
        #expect(unhealthy[0].lastMissDetail == "no match")
        #expect(unhealthy[0].source == "GitHub")
    }

    @Test func snapshotOrdersUnhealthyFirst() async {
        let health = RecipeHealth()
        await health.recordSuccess(id: "b-healthy", source: "Vendor")
        await health.recordMiss(id: "a-broken", source: "Vendor", detail: "x")
        let snap = await health.snapshot()
        #expect(snap.map(\.id) == ["a-broken", "b-healthy"])
    }

    @Test func resetClears() async {
        let health = RecipeHealth()
        await health.recordMiss(id: "x", source: "Vendor", detail: nil)
        await health.reset()
        #expect(await health.snapshot().isEmpty)
    }

    /// The health verdict is a pure date comparison — test it deterministically by
    /// constructing entries with fixed timestamps (no reliance on call timing).
    @Test func healthVerdictComparesByRecency() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        // Miss newer than success → unhealthy.
        let broken = RecipeHealth.Entry(
            id: "a", source: "Vendor", lastSuccess: older, lastMiss: newer, lastMissDetail: nil)
        #expect(!broken.isHealthy)

        // Success newer than (or equal to) the miss → healthy again.
        let recovered = RecipeHealth.Entry(
            id: "b", source: "Vendor", lastSuccess: newer, lastMiss: older, lastMissDetail: nil)
        #expect(recovered.isHealthy)

        // Never missed → healthy regardless of whether it ever succeeded.
        let pristine = RecipeHealth.Entry(
            id: "c", source: "Vendor", lastSuccess: nil, lastMiss: nil, lastMissDetail: nil)
        #expect(pristine.isHealthy)
    }
}
