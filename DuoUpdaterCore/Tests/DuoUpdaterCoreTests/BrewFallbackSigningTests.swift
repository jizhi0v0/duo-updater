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

    private static func refused(_ team: String, at version: String = "2.0") -> BrewFallbackPolicy.SigningRefusal {
        .init(team: team, version: version)
    }

    /// Answers like the brew sources do: up to date, under the cask token.
    private struct Brew: UpdateSource {
        let name = "Homebrew"
        var selfUpdating = false
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            var remote = RemoteVersion(shortVersion: "1.0", version: nil, downloadURL: nil,
                                       sourceName: name, sourceIdentifier: "example")
            remote.homebrewSelfUpdating = selfUpdating
            return remote
        }
    }

    /// An official cask marked `auto_updates` says the app's own updater is its
    /// channel: with the Settings default off it still checks other sources, and
    /// a per-copy "Homebrew Only" still holds it.
    @Test func aSelfUpdatingCaskChecksOtherSourcesUnlessTheCopySaysHomebrewOnly() async {
        let downstream = Downstream()
        let followsDefault = await UpdateChecker(
            sources: [Brew(selfUpdating: true), downstream], brewFallback: BrewFallbackPolicy(),
            installedTeam: { _ in "TEAMBREW01" }).check(app)
        #expect(followsDefault.remote?.sourceName == "GitHub")
        #expect(followsDefault.homebrewSelfUpdating)
        #expect(followsDefault.homebrewSourceIdentifier == "example")
        let held = await UpdateChecker(
            sources: [Brew(selfUpdating: true), downstream], brewFallback: BrewFallbackPolicy(blockedKeys: [key]),
            installedTeam: { _ in "TEAMBREW01" }).check(app)
        #expect(held.remote?.sourceName == "Homebrew")
        #expect(held.homebrewSelfUpdating)
        #expect(await downstream.calls == 1)
        let plain = await UpdateChecker(
            sources: [Brew(), downstream], brewFallback: BrewFallbackPolicy(),
            installedTeam: { _ in "TEAMBREW01" }).check(app)
        #expect(plain.remote?.sourceName == "Homebrew")
        #expect(!plain.homebrewSelfUpdating)
        #expect(await downstream.calls == 1)
    }

    @Test func useSettingsMeansOnForASelfUpdatingCask() {
        #expect(BrewFallbackPolicy().checksOtherSourcesByDefault(selfUpdating: true))
        #expect(!BrewFallbackPolicy().checksOtherSourcesByDefault(selfUpdating: false))
        #expect(BrewFallbackPolicy(checksOtherSourcesByDefault: true).checksOtherSourcesByDefault(selfUpdating: false))
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

    @Test(arguments: ["TEAMBREW01", ""], ["2.0", "3.0"])
    func recordedRefusalSkipsThatReleaseForTheSameCopy(stamp: String, refusedAt: String) async {
        let downstream = Downstream()
        let policy = BrewFallbackPolicy(
            checksOtherSourcesByDefault: true, signingRefusals: [key: Self.refused(stamp, at: refusedAt)])
        let result = await check(policy, team: stamp.isEmpty ? nil : stamp, sources: [downstream])
        #expect(result.remote?.sourceName == "Homebrew")
        #expect(result.brewFallbackWithheldForSigning)
        #expect(!result.hasUpdate)
    }

    /// A vendor's one-off signing mistake: 2.0 was refused, the source now
    /// offers 2.1, which gets its own try (gate 3 still decides at install).
    @Test func aNewerReleaseThanTheRefusedOneIsOfferedAgain() async {
        let downstream = Downstream()
        let policy = BrewFallbackPolicy(
            checksOtherSourcesByDefault: true, signingRefusals: [key: Self.refused("TEAMBREW01", at: "1.9")])
        let result = await check(policy, team: "TEAMBREW01", sources: [downstream])
        #expect(result.remote?.sourceName == "GitHub")
        #expect(!result.brewFallbackWithheldForSigning)
        #expect(result.hasUpdate)
    }

    @Test func aDifferentlySignedCopyIsCheckedAgain() async {
        let downstream = Downstream()
        let policy = BrewFallbackPolicy(allowedKeys: [key], signingRefusals: [key: Self.refused("TEAMBREW01")])
        let result = await check(policy, team: "TEAMUPSTRM", sources: [downstream])
        #expect(result.remote?.sourceName == "GitHub")
        #expect(await downstream.calls == 1)
    }

    @Test func homebrewOnlyNeitherReadsTheSignatureNorFlagsTheRow() async {
        let downstream = Downstream(trust: .publishedDigestOnly)
        let policy = BrewFallbackPolicy(blockedKeys: [key], signingRefusals: [key: Self.refused("TEAMBREW01")])
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
            checksOtherSourcesByDefault: true, allowedKeys: ["other"], signingRefusals: [key: Self.refused("TEAMBREW01"), "other": Self.refused("")])
        policy.set(.homebrewOnly, for: key)
        #expect(policy.override(for: key) == .homebrewOnly)
        #expect(policy.signingRefusals == ["other": Self.refused("")])
        policy.set(.checkOtherSources, for: key)
        #expect(policy.override(for: key) == .checkOtherSources)
        #expect(!policy.blockedKeys.contains(key))
        policy.set(nil, for: key)
        #expect(policy.override(for: key) == nil)
        #expect(policy.checksOtherSources(key, selfUpdating: false))
        #expect(policy.allowedKeys == ["other"])
    }

    /// `duo install` recorded a refusal while the app's row still came from an
    /// earlier check: re-choosing the selected option must clear it then, not
    /// only after the next check puts the flag on the row.
    @Test func reChoosingTheSameOptionCountsOnlyWhileARefusalHolds() {
        let held = BrewFallbackPolicy(allowedKeys: [key], signingRefusals: [key: Self.refused("TEAMBREW01")])
        #expect(held.takesChoice(.checkOtherSources, for: key, rowWithheld: false))
        let free = BrewFallbackPolicy(allowedKeys: [key])
        #expect(!free.takesChoice(.checkOtherSources, for: key, rowWithheld: false))
        #expect(free.takesChoice(.checkOtherSources, for: key, rowWithheld: true))
        #expect(free.takesChoice(.homebrewOnly, for: key, rowWithheld: false))
        #expect(!BrewFallbackPolicy().takesChoice(nil, for: key, rowWithheld: false))
    }

    /// Same marketing version, new build: a vendor that fixed its signing in a
    /// rebuild, or an app whose marketing string never moves. Builds decide
    /// only when the marketing versions agree; what cannot be told apart stays
    /// covered.
    @Test func aRefusalCoversWhatIsNotNewerByVersionOrBuild() {
        func offered(_ short: String?, _ build: String?) -> RemoteVersion {
            RemoteVersion(shortVersion: short, version: build, downloadURL: nil, sourceName: "Sparkle")
        }
        let atBuild = BrewFallbackPolicy.SigningRefusal(team: "T", version: "2.0", build: "200")
        #expect(BrewFallbackPolicy.refusalCovers(atBuild, offered("2.0", "200")))
        #expect(!BrewFallbackPolicy.refusalCovers(atBuild, offered("2.0", "201")))
        #expect(!BrewFallbackPolicy.refusalCovers(atBuild, offered("2.1", "150")))
        #expect(BrewFallbackPolicy.refusalCovers(atBuild, offered("1.9", "300")))
        #expect(BrewFallbackPolicy.refusalCovers(atBuild, offered("2.0", nil)))
        // Recorded from a source that spells only builds.
        let buildOnly = BrewFallbackPolicy.SigningRefusal(team: "T", version: "", build: "1234")
        #expect(!BrewFallbackPolicy.refusalCovers(buildOnly, offered("2.1", "1235")))
        #expect(BrewFallbackPolicy.refusalCovers(buildOnly, offered(nil, "1234")))
        #expect(!BrewFallbackPolicy.refusalCovers(buildOnly, offered(nil, "1300")))
        #expect(BrewFallbackPolicy.SigningRefusal(team: "T", refusing: offered("2.0", "200")) == atBuild)
    }

    /// A held copy whose next source fails keeps saying why it is on Homebrew.
    @Test func aHeldCopyKeepsItsNoteWhenALaterSourceFails() async {
        let policy = BrewFallbackPolicy(
            checksOtherSourcesByDefault: true, signingRefusals: [key: Self.refused("TEAMBREW01")])
        let result = await check(policy, team: "TEAMBREW01", sources: [Downstream(), Offline()])
        guard case .error = result.status else { Issue.record("Expected the later failure, got \(result.status)"); return }
        #expect(result.brewFallbackWithheldForSigning)
        #expect(result.homebrewSourceIdentifier == "example")
    }

    private struct RefusesTheOS: UpdateSource {
        let name = "Sparkle"
        let version: String
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            throw OSWindowRefused(
                OSWindowRefusal(bound: .floor(minimum: "99.0"), version: version, hostOS: "27.0.0"),
                release: RemoteVersion(shortVersion: version, version: nil, downloadURL: nil, sourceName: name))
        }
    }

    /// "Won't offer 2.0 for this macOS" says nothing new about a release
    /// already refused for its signature; a newer one is still news.
    @Test(arguments: [("2.0", false), ("2.1", true)])
    func anOSWindowRefusalOfTheRefusedReleaseIsNotNews(version: String, isNews: Bool) async {
        let policy = BrewFallbackPolicy(
            checksOtherSourcesByDefault: true, signingRefusals: [key: Self.refused("TEAMBREW01")])
        let result = await check(policy, team: "TEAMBREW01", sources: [RefusesTheOS(version: version)])
        if isNews {
            guard case .outsideOSWindow = result.status else { Issue.record("got \(result.status)"); return }
        } else {
            #expect(result.remote?.sourceName == "Homebrew")
            #expect(result.brewFallbackWithheldForSigning)
        }
    }

    @Test func aRenamedCopyKeepsItsChoiceAndRefusal() {
        var policy = BrewFallbackPolicy(blockedKeys: ["old"], signingRefusals: ["old": Self.refused("TEAMBREW01")])
        policy.migrate(from: "old", to: "new")
        #expect(policy.blockedKeys == ["new"])
        #expect(policy.signingRefusals == ["new": Self.refused("TEAMBREW01")])
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
        row.homebrewSelfUpdating = true
        let same = row.carriedForward(onto: app, remote: github, status: row.status, proven: nil)
        #expect(same.homebrewSourceIdentifier == "example")
        #expect(same.homebrewSelfUpdating)
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
        let result = await UpdateChecker(
            sources: [Brew(selfUpdating: true), Offline()], brewFallback: BrewFallbackPolicy(),
            installedTeam: { _ in nil }).check(app)
        guard case .error = result.status else { Issue.record("Expected the downstream failure, got \(result.status)"); return }
        #expect(result.homebrewSourceIdentifier == "example")
        #expect(result.homebrewSelfUpdating)
    }

    @Test func refusalsRoundTripThroughDefaults() throws {
        let suite = "brew-fallback-signing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let refusal = BrewFallbackPolicy.SigningRefusal(team: "TEAMBREW01", version: "1.5.1", build: "180")
        BrewFallbackPolicy.storeRefusals([key: refusal], in: defaults)
        #expect(BrewFallbackPolicy(defaults: defaults).signingRefusals == [key: refusal])
        // Anything else under the key (a malformed entry) is dropped, not trusted.
        defaults.set([key: "TEAMBREW01"], forKey: UpdateSettings.brewFallbackSigningRefusalsKey)
        #expect(BrewFallbackPolicy(defaults: defaults).signingRefusals.isEmpty)
        #expect(BrewFallbackPolicy.signingStamp(team: nil) == "")
    }
}
