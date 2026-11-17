import Foundation
import Testing
@testable import DuoUpdaterCore

/// Explicit opt-in for the genuine Adobe payload named by manual-fixture.py.
/// The app is already installed at the offered version. A controlled update
/// status drives the handoff route so this test cannot be mistaken for source
/// detection or an actual old-to-new Adobe update. It launches the real signed
/// installer window; the caller observes/closes that window in the VM.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DUO206X_VM_MANUAL"] == "1",
                "Requires the explicitly prepared macOS VM Adobe manual-handoff fixture"))
struct HomebrewManualVMIntegrationTests {
    private actor Signals {
        var beforeOpen = 0
        var releasedDownload = 0
        func willOpen() { beforeOpen += 1 }
        func released() { releasedDownload += 1 }
    }

    @Test func genuineSameVersionInstallerIsPreparedVerifiedAndHandedOver() async throws {
        let hardware = try await ChildProcess.run("/usr/sbin/sysctl", ["-n", "hw.model"], onCancel: .terminateChild)
        try #require(hardware.succeeded
                     && String(decoding: hardware.standardOutput, as: UTF8.self).hasPrefix("VirtualMac"),
                     "This test must never launch an installer on the host.")
        let work = URL(fileURLWithPath: "/tmp/duo206x-fix-validation/manual", isDirectory: true)
        let stateData = try Data(contentsOf: work.appendingPathComponent("fixture-state.json"))
        let state = try #require(try JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        try #require(state["handoffOnly"] as? Bool == true)
        let path = URL(fileURLWithPath: "/Applications/Adobe Connect/Adobe Connect.app")
        let scanner = AppScanner(
            locations: [path.deletingLastPathComponent()], toolbox: ToolboxInventory(managedPaths: []),
            testflight: TestFlightInventory(macRows: []), channelBinding: { _, _, _ in nil })
        let app = try #require(scanner.scan(bundlesAt: [path]).first)
        try #require(app.bundleID == "com.adobe.cefconnect.app" && app.shortVersion == "2026.10.66",
                     "Seed the genuine current Adobe copy before testing handoff.")
        let installedTeam = try await offCooperativePool { try SignatureVerifier.teamIdentifier(at: path) }
        try #require(installedTeam == "JQ525L2MZD")
        let token = "duo206x/fixtures/duo206x-manual"
        let beforeRecord = BrewLocalInventory(caskroomPaths: ["/opt/homebrew/Caskroom"])
            .installedVersion(caskToken: "duo206x-manual")
        try #require(beforeRecord == nil, "Preparation must not create a Brew installed receipt.")

        // The local cask definition pins the genuine DMG and exact manual path.
        // No direct download URL is needed by the product's Brew handoff route.
        var remote = RemoteVersion(
            shortVersion: "2026.10.66", version: nil, downloadURL: nil,
            pageURL: URL(string: "https://www.adobe.com/products/adobeconnect.html"),
            sourceName: "Homebrew", sourceIdentifier: token, requiresManualInstaller: true)
        remote.homebrewCaskVersion = "2026.10.66,11"
        remote.homebrewManualInstaller = "AdobeConnectInstaller.app"
        #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .upToDate)
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "2026.10.66"))
        let environment = InstallEnvironment(
            isHelperEnabled: true, runningAppPaths: [], stagedSelfUpdates: [:], packageInstallerAvailable: true)
        #expect(UpdatePolicy.requiresInstaller(result, environment: environment))
        #expect(!UpdatePolicy.canAutoInstall(
            result, settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite),
            environment: environment))
        let route = InstallCoordinator.route(for: result, requiresInstaller: true)
        try #require(route == .homebrew)
        let signals = Signals()
        let outcome = try await InstallCoordinator().perform(
            result, route: route, installedPopulation: [app], digestOnlyAllowed: false,
            progress: { _ in }, releaseAfterDownload: { await signals.released() },
            beforeInstallerOpen: { await signals.willOpen() })
        let staged = try #require(outcome.stagedPackageURL)
        let afterRecord = BrewLocalInventory(caskroomPaths: ["/opt/homebrew/Caskroom"])
            .installedVersion(caskToken: "duo206x-manual")
        let onDisk = try #require(scanner.scan(bundlesAt: [path]).first)
        let stagedTeam = try await offCooperativePool { try SignatureVerifier.teamIdentifier(at: staged) }
        let proof = try await offCooperativePool {
            try SignatureVerifier.verifyCodeSignatureCapturingCdhash(appAt: staged)
        }
        let record: [String: Any] = [
            "handoffOnly": true, "sourceDetectionTested": false, "oldToNewUpdateTested": false,
            "cask": token, "caskVersion": "2026.10.66,11", "manualPath": "AdobeConnectInstaller.app",
            "route": route.rawValue, "applied": outcome.applied, "stagedInstaller": staged.path,
            "stagedTeam": stagedTeam ?? "missing", "hasStagedSignatureProof": proof != nil,
            "observedVersionBefore": app.shortVersion ?? "missing", "observedVersionAfter": onDisk.shortVersion ?? "missing",
            "brewRecordCreated": afterRecord != nil, "beforeOpenCalls": await signals.beforeOpen,
            "releaseAfterDownloadCalls": await signals.releasedDownload,
        ]
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: work.appendingPathComponent("product-handoff.json"))
        print("DUO206X_MANUAL " + String(decoding: encoded, as: UTF8.self))

        #expect(!outcome.applied)
        #expect(outcome.bytesDownloaded == 0) // Brew owns the download; bytes are not guessed.
        #expect(staged.lastPathComponent == "AdobeConnectInstaller.app")
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(stagedTeam == installedTeam)
        #expect(proof != nil)
        #expect(beforeRecord == afterRecord)
        #expect(await signals.beforeOpen == 1)
        #expect(await signals.releasedDownload == 1)
        #expect(onDisk.shortVersion == app.shortVersion)
        #expect(UpdateChecker.evaluate(installed: onDisk, remote: remote) == .upToDate)
    }
}
