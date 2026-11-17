import Foundation
import Testing
@testable import DuoUpdaterCore

/// Explicit opt-in for the inert package prepared by fixed/pkg-fixture.py.
/// Positive installation is performed through the running App and its real
/// BrewAskPass panel. These assertions read the resulting app/Brew/pkg receipts.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DUO206X_VM_PKG"] == "1",
                "Requires the explicitly prepared macOS VM package fixture"))
struct HomebrewPkgVMIntegrationTests {
    @Test func actualPackageRouteAndReceipts() async throws {
        let hardware = try await ChildProcess.run("/usr/sbin/sysctl", ["-n", "hw.model"], onCancel: .terminateChild)
        try #require(String(decoding: hardware.standardOutput, as: UTF8.self).hasPrefix("VirtualMac"))
        let stage = try #require(ProcessInfo.processInfo.environment["DUO206X_VM_PKG_STAGE"])
        try #require(["before", "after", "conflict", "checksum"].contains(stage))
        let path = URL(fileURLWithPath: "/Applications/Duo206xPkg.app")
        let app = try #require(AppScanner(locations: [URL(fileURLWithPath: "/Applications")]).scan()
            .first { $0.path == path })
        let token = "duo206x/fixtures/duo206x-pkg"
        let before = stage == "before"
        #expect(app.shortVersion == (before ? "1.0" : "2.0"))
        #expect(BrewLocalInventory().installedVersion(caskToken: "duo206x-pkg") == (before ? "1.0" : "2.0"))
        let remote = try #require(try await ThirdPartyCaskSource().latestVersion(for: app))
        #expect(remote.sourceIdentifier == token)
        #expect(!remote.requiresManualInstaller && remote.homebrewManualInstaller == nil)
        let row = UpdateResult(app: app, remote: remote, status: UpdateChecker.evaluate(installed: app, remote: remote))
        #expect(InstallCoordinator.route(for: row, requiresInstaller: false) == .homebrew)
        #expect(!UpdatePolicy.requiresInstaller(row, environment: .init(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])))
        if before {
            #expect(remote.shortVersion == "2.0" && row.hasUpdate)
            #expect(!FileManager.default.fileExists(atPath: "/Applications/Duo206xDependency.app"))
        } else {
            #expect(FileManager.default.fileExists(atPath: "/Applications/Duo206xDependency.app"))
            let receipt = try await ChildProcess.run("/usr/sbin/pkgutil", ["--pkg-info-plist", "org.duo206x.fixture.pkg"], onCancel: .terminateChild)
            try #require(receipt.succeeded)
            let plist = try #require(try PropertyListSerialization.propertyList(from: receipt.standardOutput, format: nil) as? [String: Any])
            #expect(plist["pkg-version"] as? String == "2.0")
            if stage == "after" { #expect(!row.hasUpdate) }
        }
        if stage == "conflict" || stage == "checksum" {
            let installer = HomebrewInstaller()
            var failure: String?
            do {
                try await installer.fetch(caskToken: token, app: path) { _ in }
                try await installer.upgrade(caskToken: token, app: path) { _ in }
            } catch { failure = error.localizedDescription }
            let message = try #require(failure)
            #expect(message.localizedCaseInsensitiveContains(stage == "conflict" ? "conflict" : "SHA256"))
            #expect(BrewAppCask.bundleShortVersion(path.path) == "2.0")
            #expect(BrewLocalInventory().installedVersion(caskToken: "duo206x-pkg") == "2.0")
        }
        print("DUO206X_PKG stage=\(stage) app=\(app.shortVersion ?? "?") route=homebrew manual=false")
    }
}
