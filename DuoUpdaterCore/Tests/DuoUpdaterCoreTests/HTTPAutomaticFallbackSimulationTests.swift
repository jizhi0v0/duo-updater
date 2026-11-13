import Foundation
import Testing
@testable import DuoUpdaterCore

struct HTTPAutomaticFallbackSimulationTests {
    @Test(arguments: [false, true])
    func coordinatorDeltaFallbackCanRetryFullAcquisition(htmlPatch: Bool) async throws {
        let root = try DigestOnlyInstallTests.scratch("automatic-fallback")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data((htmlPatch ? "<!DOCTYPE html><title>Login</title>" : "invalid delta bytes").utf8)
        let server = try HTTPDownloadLoopbackServer([
            .init(status: 200, body: bytes),
            .init(status: 503),
        ])
        defer { server.stop() }
        let app = InstalledApp(
            name: "Fallback-\(UUID().uuidString)", bundleID: "test.automatic-fallback",
            shortVersion: "1", buildVersion: "1", path: root.appendingPathComponent("Test.app"),
            isMASApp: false, sparkleFeedURL: nil, hasSelfUpdater: false, hasSparkleUpdater: false)
        try FileManager.default.createDirectory(at: app.path, withIntermediateDirectories: true)
        let patch = DeltaPatch(fromBuild: "1", url: server.url, format: .myGo)
        let remote = RemoteVersion(shortVersion: "2", version: "2", downloadURL: server.url,
            sourceName: "Vendor", vendorInstallerKind: .zip, deltas: [patch])
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2"))
        #expect(DeltaApplier.patch(for: app, in: remote) == patch)
        let attempt = AutomaticUpdateFailurePolicy.Attempt()
        let coordinator = InstallCoordinator(runningProcesses: { [] },
            vendor: VendorInstaller(stashCachesDirectory: root.appendingPathComponent("caches"),
                                    stashApplicationSupportDirectory: root.appendingPathComponent("support")))
        await ResumableDownloadStore.$rootOverride.withValue(root.appendingPathComponent("resume")) {
            await AutomaticUpdateFailurePolicy.$attempt.withValue(attempt) {
                do {
                    _ = try await AutomaticUpdateFailurePolicy.capturing {
                        try await coordinator.perform(result, route: .vendor, installedPopulation: [app],
                            digestOnlyAllowed: false,
                            progress: AutomaticUpdateFailurePolicy.recordingProgress { _ in },
                            releaseAfterDownload: AutomaticUpdateFailurePolicy.afterDownload {})
                    }
                    Issue.record("Full archive 503 unexpectedly succeeded")
                } catch {
                    guard case .httpStatus(503) = error as? Downloader.DownloadError else {
                        Issue.record("Unexpected error before full archive refusal: \(error)")
                        return
                    }
                }
            }
        }
        #expect(server.requests.count == 2)
        #expect(server.unexpectedRequests.isEmpty)
        #expect(attempt.evidence.allowedFallbackAcquisition)
        if !htmlPatch { #expect(attempt.evidence.acquisitionFinished) }
        #expect(try #require(attempt.failure(or: "missing")).disposition == .retryAcquisition)
        #expect(!attempt.evidence.sideEffectsStarted)
    }
}
