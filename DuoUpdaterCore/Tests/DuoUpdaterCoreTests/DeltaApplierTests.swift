import Testing
import Foundation
@testable import DuoUpdaterCore

/// Choosing an incremental patch, and refusing to choose the wrong one.
///
/// The numbers are Keka's real 1.6.7 feed (fetched 2026-08-23): eight patches
/// spanning builds 5600–5715 against a 32.86 MB archive. A full round trip
/// through this selection — download 519,746 B, patch, swap — was run against the
/// live feed before these were written.
struct DeltaApplierTests {

    private func remote(deltas: [DeltaPatch], version: String = "5729") -> RemoteVersion {
        RemoteVersion(
            shortVersion: "1.6.7", version: version,
            downloadURL: URL(string: "https://example.com/Keka-1.6.7.zip"),
            downloadSize: 32_861_805, edSignature: "archive-sig",
            sourceName: "Sparkle", deltas: deltas)
    }

    private func patch(from build: String, size: Int64 = 519_746) -> DeltaPatch {
        DeltaPatch(
            fromBuild: build,
            url: URL(string: "https://example.com/\(build)-5729.delta")!,
            size: size, edSignature: "patch-sig-\(build)")
    }

    private func app(build: String?, short: String = "1.6.5") -> InstalledApp {
        InstalledApp(
            name: "Keka", bundleID: "com.aone.keka", shortVersion: short,
            buildVersion: build, path: URL(fileURLWithPath: "/Applications/Keka.app"),
            isMASApp: false, sparkleFeedURL: URL(string: "https://u.keka.io"),
            hasSelfUpdater: false, hasSparkleUpdater: true)
    }

    @Test func picksThePatchCutAgainstTheInstalledBuild() throws {
        let r = remote(deltas: [patch(from: "5707", size: 1_345_567), patch(from: "5715")])
        let chosen = try #require(DeltaApplier.patch(for: app(build: "5715"), in: r))
        #expect(chosen.fromBuild == "5715")
        #expect(chosen.size == 519_746)
    }

    /// Skipping a few releases is the ordinary case, and it is not an error — the
    /// vendor publishes a handful of patches and everyone else takes the archive.
    @Test func noPatchForABuildTheFeedDoesNotCover() {
        let r = remote(deltas: [patch(from: "5707"), patch(from: "5715")])
        #expect(DeltaApplier.patch(for: app(build: "5600"), in: r) == nil)
    }

    /// The match is on `CFBundleVersion` because that is what `sparkle:deltaFrom`
    /// carries. Keka 1.6.5 is build 5715 — matching on the marketing string would
    /// find nothing here, and on an app whose two numbers overlap differently it
    /// could find the wrong patch, which then fails to apply against a bundle it
    /// was never cut for.
    @Test func matchesOnBuildNotMarketingVersion() {
        let r = remote(deltas: [patch(from: "1.6.5")])
        #expect(DeltaApplier.patch(for: app(build: "5715"), in: r) == nil)
    }

    @Test func noBuildVersionMeansNoPatch() {
        let r = remote(deltas: [patch(from: "5715")])
        #expect(DeltaApplier.patch(for: app(build: nil), in: r) == nil)
    }

    /// The overwhelmingly common shape: of the eleven Sparkle feeds readable on
    /// this machine, only Keka's published patches the installed build could use.
    @Test func aFeedWithoutPatchesSelectsNothing() {
        #expect(DeltaApplier.patch(for: app(build: "5715"), in: remote(deltas: [])) == nil)
    }

    /// A patch is signed separately from the archive. Carrying the archive's
    /// signature onto a downloaded patch would fail verification every time, so the
    /// two must stay distinguishable all the way to the verifier.
    @Test func patchCarriesItsOwnSignature() throws {
        let r = remote(deltas: [patch(from: "5715")])
        let chosen = try #require(DeltaApplier.patch(for: app(build: "5715"), in: r))
        #expect(chosen.edSignature == "patch-sig-5715")
        #expect(chosen.edSignature != r.edSignature)
    }

    /// Garbage in, error out — never a half-written bundle presented as an update.
    @Test func aCorruptPatchFailsRatherThanProducingABundle() throws {
        guard let tool = DeltaApplier.toolURL() else {
            // No embedded tool in this build (plain `swift test` without the app
            // installed); the selection tests above still cover the logic.
            return
        }
        _ = tool
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-delta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let fakeApp = scratch.appendingPathComponent("Old.app")
        try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        let junk = scratch.appendingPathComponent("junk.delta")
        try Data("not a patch".utf8).write(to: junk)
        let out = scratch.appendingPathComponent("New.app")

        #expect(throws: (any Error).self) {
            try DeltaApplier.apply(installedApp: fakeApp, patch: junk, destination: out)
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    /// What makes attempting an unverified patch safe: a failure on this route is
    /// marked recoverable, so the caller retries with the full archive instead of
    /// surfacing an install failure. The message still reads as the real cause.
    @Test func aPatchFailureReadsAsItsUnderlyingCause() {
        let underlying = DeltaApplier.DeltaError.applyFailed(code: 3, message: "corrupt")
        let wrapped = DeltaRouteFailure(underlying: underlying)
        #expect(wrapped.errorDescription == underlying.errorDescription)
    }
}
