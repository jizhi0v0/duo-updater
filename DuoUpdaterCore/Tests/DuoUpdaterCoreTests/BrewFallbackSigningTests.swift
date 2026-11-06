import Foundation
import Testing
@testable import DuoUpdaterCore

/// A brew copy that may check other sources still stays on Homebrew when the
/// other source's build is signed by someone else: visibly so before download
/// (the rule says the release has no Team ID), or after an install from it was
/// refused for its signature.
@Suite struct BrewFallbackSigningTests {
    private let app = InstalledApp(
        name: "Example", bundleID: "example.app", shortVersion: "1.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/Example.app"), isMASApp: false, sparkleFeedURL: nil)

    private var key: String { InstallPreferenceKey.key(for: app) }

    /// Answers like the brew sources do: up to date, under the cask token.
    private struct Brew: UpdateSource {
        let name = "Homebrew"
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            RemoteVersion(shortVersion: "1.0", version: nil, downloadURL: nil,
                          sourceName: name, sourceIdentifier: "example")
        }
    }

    private actor Downstream: UpdateSource {
        nonisolated let name: String
        let trust: InstallTrust
        var calls = 0
        init(name: String = "GitHub", trust: InstallTrust = .developerID) {
            self.name = name
            self.trust = trust
        }
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return RemoteVersion(
                shortVersion: "2.0", version: nil, downloadURL: URL(string: "https://example.com/app.dmg"),
                sourceName: name, vendorInstallerKind: .dmg, installTrust: trust)
        }
    }

    private func check(
        _ policy: BrewFallbackPolicy, team: String?, sources: [any UpdateSource]
    ) async -> UpdateResult {
        await UpdateChecker(
            sources: [Brew()] + sources, brewFallback: policy,
            installedTeam: { _ in team }).check(app)
    }

    @Test func digestOnlyReleaseIsSkippedForASignedBrewCopy() async {
        let adHoc = Downstream(trust: .publishedDigestOnly)
        let result = await check(BrewFallbackPolicy(allowedKeys: [key]), team: "TEAMBREW01", sources: [adHoc])
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.brewFallbackWithheldForSigning)
        #expect(!result.hasUpdate)
        #expect(await adHoc.calls == 1)
    }

    @Test func aSkippedSourceDoesNotHideALaterOne() async {
        let adHoc = Downstream(trust: .publishedDigestOnly)
        let signed = Downstream(name: "Sparkle")
        let result = await check(
            BrewFallbackPolicy(checksOtherSourcesByDefault: true), team: "TEAMBREW01", sources: [adHoc, signed])
        #expect(result.remote?.sourceName == "Sparkle")
        #expect(result.homebrewSourceIdentifier == "example")
        #expect(!result.brewFallbackWithheldForSigning)
        #expect(result.hasUpdate)
    }

    @Test func digestOnlyReleaseStillReachesAnUnsignedBrewCopy() async {
        let adHoc = Downstream(trust: .publishedDigestOnly)
        let result = await check(BrewFallbackPolicy(allowedKeys: [key]), team: nil, sources: [adHoc])
        #expect(result.remote?.sourceName == "GitHub")
        #expect(!result.brewFallbackWithheldForSigning)
    }

    @Test func developerIDReleaseReachesASignedBrewCopy() async {
        let result = await check(BrewFallbackPolicy(allowedKeys: [key]), team: "TEAMBREW01", sources: [Downstream()])
        #expect(result.remote?.sourceName == "GitHub")
        #expect(result.hasUpdate)
    }

    @Test(arguments: ["TEAMBREW01", ""])
    func recordedRefusalKeepsTheSameCopyOnHomebrewWithoutAsking(stamp: String) async {
        let downstream = Downstream()
        let policy = BrewFallbackPolicy(checksOtherSourcesByDefault: true, signingRefusals: [key: stamp])
        let result = await check(policy, team: stamp.isEmpty ? nil : stamp, sources: [downstream])
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.brewFallbackWithheldForSigning)
        #expect(await downstream.calls == 0)
    }

    @Test func aDifferentlySignedCopyIsCheckedAgain() async {
        let downstream = Downstream()
        let policy = BrewFallbackPolicy(allowedKeys: [key], signingRefusals: [key: "TEAMBREW01"])
        let result = await check(policy, team: "TEAMUPSTRM", sources: [downstream])
        #expect(result.remote?.sourceName == "GitHub")
        #expect(await downstream.calls == 1)
    }

    @Test func homebrewOnlyNeitherReadsTheSignatureNorFlagsTheRow() async {
        let downstream = Downstream(trust: .publishedDigestOnly)
        let policy = BrewFallbackPolicy(blockedKeys: [key], signingRefusals: [key: "TEAMBREW01"])
        let result = await UpdateChecker(
            sources: [Brew(), downstream], brewFallback: policy,
            installedTeam: { _ in Issue.record("No signature read without a fallback"); return nil }).check(app)
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(!result.brewFallbackWithheldForSigning)
        #expect(await downstream.calls == 0)
    }

    @Test func signingRefusalsAreTheIdentityGatesOnly() {
        typealias E = SignatureVerifier.VerifyError
        let refusals: [E] = [
            .noTeamIdentifier(which: "downloaded"),
            .teamIdentifierMismatch(installed: "A", downloaded: "B"),
            .teamIdentifierAppeared(downloaded: "B"),
            .notAdHocSigned, .signingKindChanged, .designatedRequirementNotSatisfied(-67050),
            .bundleIdentifierMismatch(installed: "a", downloaded: "b"),
        ]
        for error in refusals { #expect(BrewFallbackPolicy.isSigningRefusal(error), "\(error)") }
        let others: [any Error] = [
            E.edSignatureInvalid, E.publishedDigestMismatch, E.architectureDowngrade(installed: "arm64", downloaded: "x86_64"),
            URLError(.notConnectedToInternet), CancellationError(),
        ]
        for error in others { #expect(!BrewFallbackPolicy.isSigningRefusal(error), "\(error)") }
    }

    @Test func onlyABrewCopyTakingAnotherSourceCountsAsAFallbackInstall() {
        let other = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: "GitHub")
        let brew = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: "Homebrew")
        var fallback = UpdateResult(app: app, remote: other, status: .updateAvailable(latest: "2.0"))
        fallback.homebrewSourceIdentifier = "example"
        var viaBrew = UpdateResult(app: app, remote: brew, status: .updateAvailable(latest: "2.0"))
        viaBrew.homebrewSourceIdentifier = "example"
        let direct = UpdateResult(app: app, remote: other, status: .updateAvailable(latest: "2.0"))
        #expect(BrewFallbackPolicy.isFallbackInstall(fallback))
        #expect(!BrewFallbackPolicy.isFallbackInstall(viaBrew))
        #expect(!BrewFallbackPolicy.isFallbackInstall(direct))
    }

    @Test func choosingInTheMenuReplacesTheOtherChoiceAndForgetsARefusal() {
        var policy = BrewFallbackPolicy(
            checksOtherSourcesByDefault: true, allowedKeys: ["other"], signingRefusals: [key: "TEAMBREW01", "other": ""])
        policy.set(.homebrewOnly, for: key)
        #expect(policy.override(for: key) == .homebrewOnly)
        #expect(policy.signingRefusals == ["other": ""])
        policy.set(.checkOtherSources, for: key)
        #expect(policy.override(for: key) == .checkOtherSources)
        #expect(!policy.blockedKeys.contains(key))
        policy.set(nil, for: key)
        #expect(policy.override(for: key) == nil)
        #expect(policy.checksOtherSources(key))
        #expect(policy.allowedKeys == ["other"])
    }

    @Test func aRenamedCopyKeepsItsChoiceAndRefusal() {
        var policy = BrewFallbackPolicy(blockedKeys: ["old"], signingRefusals: ["old": "TEAMBREW01"])
        policy.migrate(from: "old", to: "new")
        #expect(policy.blockedKeys == ["new"])
        #expect(policy.signingRefusals == ["new": "TEAMBREW01"])
        policy.migrate(from: "new", to: "new")
        #expect(policy.blockedKeys == ["new"])
    }

    /// A local rescan rebuilds rows with `carriedForward`. Dropping the brew
    /// owner there took a row another source answered out of the brew menu and
    /// out of the Settings default's re-check, until the next network check.
    @Test func aRescanKeepsTheBrewOwnerAndTheSigningHoldOfTheSameCopy() {
        let github = RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: "GitHub")
        var row = UpdateResult(app: app, remote: github, status: .updateAvailable(latest: "2.0"))
        row.homebrewSourceIdentifier = "example"
        row.brewFallbackWithheldForSigning = true
        let same = row.carriedForward(onto: app, remote: github, status: row.status, proven: nil)
        #expect(same.homebrewSourceIdentifier == "example")
        #expect(same.brewFallbackWithheldForSigning)
        let moved = InstalledApp(name: app.name, bundleID: app.bundleID, shortVersion: "2.0", buildVersion: nil,
                                 path: app.path, isMASApp: false, sparkleFeedURL: nil)
        let next = row.carriedForward(onto: moved, remote: github, status: .upToDate, proven: nil)
        #expect(next.homebrewSourceIdentifier == "example")
        #expect(!next.brewFallbackWithheldForSigning)
    }

    private struct Offline: UpdateSource {
        let name = "Sparkle"
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            throw URLError(.cannotConnectToHost)
        }
    }

    /// Transmission, 2026-11-07: brew said up to date, the next source could
    /// not connect, and the error row lost the brew owner — so its menu lost the
    /// choice and the Settings default's re-check skipped it.
    @Test func aFailedDownstreamCheckStillNamesTheBrewOwner() async {
        let result = await check(BrewFallbackPolicy(checksOtherSourcesByDefault: true), team: nil, sources: [Offline()])
        guard case .error = result.status else { Issue.record("Expected the downstream failure, got \(result.status)"); return }
        #expect(result.homebrewSourceIdentifier == "example")
    }

    @Test func refusalsRoundTripThroughDefaults() throws {
        let suite = "brew-fallback-signing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([key: "TEAMBREW01"], forKey: UpdateSettings.brewFallbackSigningRefusalsKey)
        #expect(BrewFallbackPolicy(defaults: defaults).signingRefusals == [key: "TEAMBREW01"])
        #expect(BrewFallbackPolicy.signingStamp(team: nil) == "")
    }
}
