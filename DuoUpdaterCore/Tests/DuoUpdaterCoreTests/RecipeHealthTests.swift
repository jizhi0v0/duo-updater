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

    /// PR #201 review, blocker #1: keying storage by `id` alone let a bundle id
    /// tracked under two sources collide. The concrete failure this caused: a
    /// broken Vendor recipe for a bundle id (e.g. Notion, whose vendor page
    /// changed) records a miss, `UpdateChecker` falls through to the next source
    /// on the thrown error, and if THAT source (e.g. `ElectronManifestSource`,
    /// reading `app-update.yml` for the same bundle id) resolves fine, the old
    /// single-key storage let that unrelated success overwrite the Vendor miss —
    /// the broken Vendor recipe vanished from the diagnostics panel entirely.
    /// Keying on `(id, source)` keeps the two recipes' health independent.
    @Test func sameIDUnderDifferentSourcesTracksIndependently() async throws {
        let health = RecipeHealth()
        await health.recordMiss(id: "notion.id", source: "Vendor", detail: "vendor page changed")
        await health.recordSuccess(id: "notion.id", source: "Electron")

        let snap = await health.snapshot()
        #expect(snap.count == 2)

        let vendor = try #require(snap.first { $0.source == "Vendor" })
        #expect(vendor.isHealthy == false)
        #expect(vendor.lastMissDetail == "vendor page changed")

        let electron = try #require(snap.first { $0.source == "Electron" })
        #expect(electron.isHealthy == true)

        // Both share `id` by design — that's the whole point of the scenario —
        // but a consumer that needs a truly unique identifier (the diagnostics
        // view's `ForEach`) must not collide on it.
        #expect(vendor.id == electron.id)
        #expect(vendor.key != electron.key)

        // And a later Vendor success must not touch the Electron entry, nor vice
        // versa — the two recipes stay independently trackable indefinitely, not
        // just across this one miss/success pair.
        await health.recordSuccess(id: "notion.id", source: "Vendor")
        let recovered = try #require(await health.snapshot().first { $0.source == "Vendor" })
        #expect(recovered.isHealthy == true)
        let electronStillThere = try #require(await health.snapshot().first { $0.source == "Electron" })
        #expect(electronStillThere.isHealthy == true)
        #expect(await health.snapshot().count == 2)
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
