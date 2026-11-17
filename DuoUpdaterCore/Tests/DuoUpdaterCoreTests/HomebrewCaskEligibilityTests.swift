import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct HomebrewCaskEligibilityTests {
    private func app() -> InstalledApp {
        InstalledApp(
            name: "Eligibility fixture", bundleID: "org.example.eligibility-fixture",
            shortVersion: "1.0", buildVersion: "1.0",
            path: URL(fileURLWithPath: "/Applications/ZZEligibilityFixture/Fixture.app"),
            isMASApp: false, sparkleFeedURL: nil)
    }

    private func index(_ dependencyJSON: String, variation: String = "") throws -> CaskIndex {
        let json = """
            [{"token":"zz-eligibility-fixture","version":"2.0","url":"https://example.invalid/fixture.dmg",
              "artifacts":[{"app":["Fixture.app"]}],"depends_on":\(dependencyJSON)\(variation)}]
            """
        return try HomebrewCaskCatalog.index(fromCatalogJSON: Data(json.utf8), platformTag: "arm64_tahoe")
    }

    private func remote(_ index: CaskIndex, os: String = "26.1", arch: HostArch = .arm64) async throws -> RemoteVersion {
        let source = HomebrewCaskSource(
            catalog: HomebrewCaskCatalog(testIndex: index),
            inventory: BrewLocalInventory(installedTokens: ["zz-eligibility-fixture"],
                                          installedVersions: ["zz-eligibility-fixture": "1.0"]),
            hostOSVersion: os, hostArchitecture: arch)
        return try #require(await source.latestVersion(for: app()))
    }

    @Test func intelOnlyKeepsTheOwnerAndVersionButWithholdsTheAction() async throws {
        let release = try await remote(index(#"{"arch":[{"type":"intel","bits":64}]}"#))
        #expect(release.sourceIdentifier == "zz-eligibility-fixture")
        #expect(release.homebrewIncompatibility == .architecture(required: [.x86_64], host: .arm64))
        let result = UpdateResult(app: app(), remote: release,
                                  status: UpdateChecker.evaluate(installed: app(), remote: release))
        #expect(result.hasUpdate)
        #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
        #expect(!UpdatePolicy.requiresInstaller(result, environment: environment))
    }

    @Test func matchingArchitectureAndAlternativesRemainInstallable() async throws {
        for requirement in [
            #"{"arch":[{"type":"arm","bits":64}]}"#,
            #"{"arch":[{"type":"intel","bits":64},{"type":"arm","bits":[64]}]}"#,
            #"{}"#,
        ] {
            let release = try await remote(index(requirement))
            #expect(release.homebrewIncompatibility == nil)
            let result = UpdateResult(app: app(), remote: release, status: .updateAvailable(latest: "2.0"))
            #expect(UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
        }
    }

    @Test func platformVariationReplacesArchitectureAndOSRequirementsTogether() async throws {
        let variation = #", "variations":{"arm64_tahoe":{"depends_on":{"arch":[{"type":"arm","bits":64}],"macos":{">=":["26"]}}}}"#
        let parsed = try index(#"{"arch":[{"type":"intel","bits":64}],"macos":{"==":["15"]}}"#,
                               variation: variation)
        let entry = try #require(parsed.byToken["zz-eligibility-fixture"])
        #expect(entry.architectures == [.arm64])
        #expect(entry.macOS == CaskMacOSRequirement(comparison: .atLeast, versions: ["26"]))
        #expect(try await remote(parsed).homebrewIncompatibility == nil)
    }

    @Test func unsupportedMacOSMembershipKeepsTheOwnerAndExplainsTheGap() async throws {
        let release = try await remote(index(#"{"macos":{"==":["15","26"]}}"#), os: "27.2")
        #expect(release.sourceIdentifier == "zz-eligibility-fixture")
        #expect(release.homebrewIncompatibility == .macOS(
            required: CaskMacOSRequirement(comparison: .exactly, versions: ["15", "26"]), host: "27.2"))
        #expect(try await remote(index(#"{"macos":{"==":["15","26"]}}"#)).homebrewIncompatibility == nil)
    }

    @Test func knownRefusalBlocksBothBrewAndInstallerRoutesBeforeAnyCommand() async throws {
        let refusal = CaskIncompatibility.architecture(required: [.x86_64], host: .arm64)
        let root = TestScratch.directory("cask-eligibility")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("brew")
        let marker = root.appendingPathComponent("started")
        try "#!/bin/sh\ntouch '\(marker.path)'\nexit 1\n".write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let coordinator = InstallCoordinator()
        try await LoginShellEnvironment.$homebrewVariablesOverride.withValue([:]) {
            try await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                try await HomebrewInstaller.$ownershipOverride.withValue([]) {
                    for manual in [false, true] {
                        var release = RemoteVersion(
                            shortVersion: "2.0", version: nil, downloadURL: URL(string: "https://example.invalid/fixture.pkg"),
                            sourceName: "Homebrew", sourceIdentifier: "zz-eligibility-fixture",
                            requiresManualInstaller: manual)
                        release.homebrewIncompatibility = refusal
                        let result = UpdateResult(app: app(), remote: release, status: .updateAvailable(latest: "2.0"))
                        #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
                        #expect(!UpdatePolicy.requiresInstaller(result, environment: environment))
                        await #expect(throws: CaskIncompatibility.self) {
                            _ = try await coordinator.perform(
                                result, route: manual ? .installer : .homebrew,
                                installedPopulation: [result.app], digestOnlyAllowed: false, progress: { _ in })
                        }
                    }
                }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    private var settings: UpdateSettings {
        UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)
    }

    private var environment: InstallEnvironment {
        InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
    }
}
