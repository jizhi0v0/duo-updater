import Foundation
import Testing
import DuoUpdaterCore
@testable import DuoKit

struct AuditedFeedVerificationTests {
    private func target(_ registry: String = "electron", owns: Bool = true) -> InstallVerify.Target {
        InstallVerify.Target(
            recipeID: "\(registry):com.example.app:stable", registry: registry,
            bundleID: "com.example.app", probeHost: "example.com", resolve: {
                ProbeOutcome(recipeID: "fixture", bundleID: "com.example.app", channel: .stable,
                             remote: nil, failure: nil)
            }, ownsResolutionFinding: owns)
    }
    private func resolve(_ failure: ProbeFailure?, owns: Bool = true) -> InstallVerify.Item {
        let target = target(owns: owns)
        let outcome = ProbeOutcome(recipeID: target.recipeID, bundleID: target.bundleID,
                                   channel: .stable, remote: nil, failure: failure,
                                   httpStatus: { if case .httpStatus(let code) = failure { return code }; return nil }())
        var item = InstallVerify.Item(recipeID: target.recipeID, registry: target.registry,
                                     bundleID: target.bundleID, probeHost: target.probeHost, status: .unresolved)
        InstallVerify.applyResolutionFailure(outcome, target: target, to: &item)
        return item
    }

    @Test func missingGenericFeedsAreNeverSilentlySkipped() {
        #expect(InstallVerify.finding(resolve(.httpStatus(404))).status == .broken)
        #expect(InstallVerify.finding(resolve(.versionPatternNoMatch(sampleBytes: 20))).status == .broken)
        #expect(InstallVerify.finding(resolve(nil)).status == .broken) // version-only / missing installer
        #expect(InstallVerify.finding(resolve(.httpStatus(503))).status == .infra)
        #expect(InstallVerify.finding(resolve(.transport(urlErrorCode: -1001, "timeout"))).status == .infra)
        #expect(InstallVerify.finding(resolve(.notApplicable("not for this host"))).status == .skipped)
        #expect(InstallVerify.finding(resolve(.httpStatus(404), owns: false)).status == .skipped)
    }

    @Test func genericTargetsExistWithoutInstalledAppsAndKeepDistinctCopyGroups() {
        let all = InstallVerify.auditedTargets()
        #expect(all.count == AuditedUpdateFeeds.entries.count)
        #expect(all.allSatisfy { $0.ownsResolutionFinding })
        #expect(Set(all.map(\.recipeID)).isSubset(of: InstallVerify.liveRecipeIDs()))
        let douchat = InstallVerify.auditedTargets(only: ["ai.thinkany.douchat"])
        #expect(douchat.count == 2)
        #expect(Set(douchat.map(\.recipeID)).count == 2)
        #expect(InstallVerify.auditedTargets(only: ["does-not-exist"]).isEmpty)
    }

    @Test func aRecordedKeyAlwaysTakesPrecedenceOverTheAuditedKey() throws {
        let entry = try #require(AuditedUpdateFeeds.entries.first {
            if case .sparkle(_, let key, _) = $0.source { return key != nil }; return false
        })
        let targets = InstallVerify.auditedTargets(entries: [entry], recordedKeys: [entry.recipeID: "old-key"])
        #expect(targets.first?.recordedSparkleKey == "old-key")
    }

    @Test func aFailedAuditedAnchorCannotBeReplacedByTheFirstDownloadedKey() throws {
        let entry = try #require(AuditedUpdateFeeds.entries.first {
            if case .sparkle(_, let key, _) = $0.source { return key != nil }; return false
        })
        var store = InstallIdentities()
        for _ in 0..<2 {
            var item = InstallVerify.Item(recipeID: entry.recipeID, registry: "sparkle",
                bundleID: entry.bundleID, probeHost: "example.com", status: .warn)
            item.identity = ArtifactInspection.Identity(
                signedIdentifier: entry.bundleID, bundleIdentifier: entry.bundleID, teamIdentifier: nil,
                shortVersion: "2", bundleVersion: "2", architectures: ["arm64"],
                minimumSystemVersion: nil, sparklePublicKey: "unreviewed-new-key")
            item.warnings = ["sparkleArchiveSignatureChanged: does not verify"]
            InstallVerify.compare(&item, with: &store, at: Date())
            #expect(store.entries[entry.recipeID] == nil)
            #expect(item.status == .warn && !item.warnings.isEmpty)
            let next = InstallVerify.auditedTargets(entries: [entry],
                recordedKeys: store.entries.compactMapValues(\.sparklePublicKey))
            #expect(next.first?.recordedSparkleKey != "unreviewed-new-key")
        }
    }

    @Test func downloadedArchiveFormatsIncludeProductionTarVariants() {
        #expect(ArtifactInspection.installerKind(for: URL(string: "https://downloads.vivaldi.com/Vivaldi.tar.xz")!) == .tarGz)
        for suffix in ["tar.bz2", "tar", "tgz", "tbz", "gz", "bz2", "xz"] {
            #expect(ArtifactInspection.installerKind(for: URL(fileURLWithPath: "/scratch/App.\(suffix)")) == .tarGz)
        }
        // A redirect endpoint is not rejected before the download. Its actual
        // response filename selects the format in ArtifactInspection.inspect.
        #expect(ArtifactInspection.installerKind(for: URL(fileURLWithPath: "/scratch/HandBrake.dmg")) == .dmg)
    }

    @Test func aMissingInventoryTargetPreservesHistoryAndProducesAnActionableFinding() {
        let id = "sparkle:com.example.retired:stable"
        let items = InstallVerify.missingInventoryItems(
            identityIDs: [id], baselineIDs: ["install:\(id)", "install:electron:com.other.app:stable"],
            live: ["electron:com.other.app:stable"], only: [])
        #expect(items.count == 1)
        #expect(items.first?.recipeID == id)
        #expect(items.first.map(InstallVerify.finding)?.status == .warn)
        #expect(InstallVerify.missingInventoryItems(
            identityIDs: [id], baselineIDs: [], live: [], only: ["different.app"]).isEmpty)
        #expect(Reconcile.qualifier(recipeID: "install:electron:ai.thinkany.douchat:stable:legacy") == "stable:legacy")
        #expect(Reconcile.qualifier(recipeID: "install:sparkle:run.kuvo.app:stable") == nil)
    }

    @Test func aVerifiedSparkleKeyIsAValidNoTeamRouteButCannotHideABundleMismatch() {
        let identity = ArtifactInspection.Identity(
            signedIdentifier: "com.other.app", bundleIdentifier: "com.other.app", teamIdentifier: nil,
            shortVersion: "1", bundleVersion: "1", architectures: ["arm64"],
            minimumSystemVersion: nil, sparklePublicKey: "key")
        let remote = RemoteVersion(shortVersion: "1", version: "1", downloadURL: nil, sourceName: "Sparkle")
        let warnings = InstallVerify.warnings(identity: identity, remote: remote,
                                             recipeBundleID: "com.example.app", sparkleSignatureVerified: true)
        #expect(warnings.contains { $0.hasPrefix("bundleIDMismatch:") })
        #expect(InstallVerify.warnings(identity: identity, remote: remote,
                                      recipeBundleID: "com.other.app").contains { $0.hasPrefix("noTeamIdentifier:") })
    }
    @Test func aVerifiedArchiveCannotHideRemovedKeysOrWrongSignedIdentityOnFirstSighting() {
        let remote = RemoteVersion(shortVersion: "1", version: "1", downloadURL: nil, sourceName: "Sparkle")
        let valid = ArtifactInspection.Identity(
            signedIdentifier: "com.example.app", bundleIdentifier: "com.example.app", teamIdentifier: nil,
            shortVersion: "1", bundleVersion: "1", architectures: ["arm64"],
            minimumSystemVersion: nil, sparklePublicKey: "old-key")
        #expect(InstallVerify.warnings(identity: valid, remote: remote,
            recipeBundleID: "com.example.app", sparkleSignatureVerified: true).isEmpty)
        var noKey = valid; noKey.sparklePublicKey = nil
        var wrongSignedID = valid; wrongSignedID.signedIdentifier = "linker-generated-other-id"
        var noPlistID = valid; noPlistID.bundleIdentifier = nil
        for identity in [noKey, wrongSignedID, noPlistID] {
            let warnings = InstallVerify.warnings(identity: identity, remote: remote,
                recipeBundleID: "com.example.app", sparkleSignatureVerified: true)
            #expect(!warnings.isEmpty)
            var item = InstallVerify.Item(recipeID: "sparkle:com.example.app:stable", registry: "sparkle",
                bundleID: "com.example.app", probeHost: "example.com", status: .warn)
            item.identity = identity; item.warnings = warnings
            var store = InstallIdentities()
            for _ in 0..<2 {
                InstallVerify.compare(&item, with: &store, at: Date())
                #expect(store.entries.isEmpty)
                #expect(item.status == .warn)
            }
        }
    }

}
