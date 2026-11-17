import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct HomebrewExecutionCompatibilityTests {
    @Test func pinnedFormulaeAreNotOfferedButUnpinnedFormulaeRemain() {
        let data = Data(#"{"formulae":[{"name":"pinned","current_version":"2","installed_versions":["1"],"pinned":true},{"name":"free","current_version":"2","installed_versions":["1"],"pinned":false},{"name":"legacy","current_version":"2","installed_versions":["1"]}]}"#.utf8)
        #expect(Set(BrewFormulaService.parse(data).map(\.name)) == ["free", "legacy"])
    }

    @Test func foreignOrUnavailablePrefixesAreRefused() throws {
        try HomebrewInstaller.validateOwnerPrefix("/opt/homebrew", selectedBrew: "/opt/homebrew/bin/brew")
        try HomebrewInstaller.validateOwnerPrefix(nil, selectedBrew: nil)
        #expect(throws: HomebrewInstaller.UnsupportedPrefix.self) {
            try HomebrewInstaller.validateOwnerPrefix("/usr/local", selectedBrew: "/opt/homebrew/bin/brew")
        }
        #expect(throws: HomebrewInstaller.UnsupportedPrefix.self) {
            try HomebrewInstaller.validateOwnerPrefix("/usr/local", selectedBrew: nil)
        }
    }

    private final class ClockAndCount: @unchecked Sendable {
        private let lock = NSLock()
        private var time = Date(timeIntervalSince1970: 100)
        private var count = 0
        func now() -> Date { lock.withLock { time } }
        func advance() { lock.withLock { time.addTimeInterval(6) } }
        func resolve() -> [String: String] {
            lock.withLock { count += 1; return ["HOMEBREW_FIXTURE": "\(count)"] }
        }
        var resolutions: Int { lock.withLock { count } }
    }

    @Test func commandSnapshotCoalescesReadsAndRefreshesAfterExpiry() async {
        let state = ClockAndCount()
        let snapshot = LoginShellEnvironment.CommandSnapshot(now: { state.now() }, resolve: { state.resolve() })
        await withTaskGroup(of: [String: String]?.self) { group in
            for _ in 0..<20 { group.addTask { await snapshot.variables() } }
            for await value in group { #expect(value == ["HOMEBREW_FIXTURE": "1"]) }
        }
        #expect(state.resolutions == 1)
        state.advance()
        #expect(await snapshot.variables() == ["HOMEBREW_FIXTURE": "2"])
        #expect(state.resolutions == 2)
    }

    @Test func shellVariablesAndExplicitOperationalFlagsHaveDefinedPrecedence() async {
        await LoginShellEnvironment.$homebrewVariablesOverride.withValue([
            "HOMEBREW_AUTO_UPDATE_SECS": "2055", "HOMEBREW_NO_AUTO_UPDATE": "shell",
            "PATH": "/untrusted/shell/path", "UNRELATED_SECRET": "not-forwarded"
        ]) {
            let env = await LoginShellEnvironment.commandEnvironment(extra: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
            #expect(env["HOMEBREW_AUTO_UPDATE_SECS"] == "2055")
            #expect(env["HOMEBREW_NO_AUTO_UPDATE"] == "1")
            #expect(env["PATH"] != "/untrusted/shell/path")
            #expect(env["UNRELATED_SECRET"] != "not-forwarded")
        }
    }

    @Test func normalReadAndCaskFetchReceiveShellVariables() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brew-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("brew")
        let log = root.appendingPathComponent("commands")
        try """
            #!/bin/sh
            printf '%s|%s|%s\\n' "$*" "$HOMEBREW_NO_AUTO_UPDATE" "$HOMEBREW_AUTO_UPDATE_SECS" >> '\(log.path)'
            exit 0

            """.write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        try await LoginShellEnvironment.$homebrewVariablesOverride.withValue([
            "HOMEBREW_NO_AUTO_UPDATE": "shell", "HOMEBREW_AUTO_UPDATE_SECS": "2055"
        ]) {
            let executor = BrewFormulaService.executor(brewPath: { brew.path })
            _ = try await executor(["config"])
            try await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                try await HomebrewInstaller().fetch(caskToken: "zzfixture-env") { _ in }
            }
        }
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == [
            "config|1|2055",
            "install --cask --force --dry-run -- zzfixture-env|shell|2055",
            "fetch --cask -- zzfixture-env|1|2055",
        ])
    }

    @Test func staleForeignOwnershipRefusesFetchAndApplyBeforeBrewStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brew-foreign-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("brew")
        let log = root.appendingPathComponent("executed")
        try "#!/bin/sh\ntouch '\(log.path)'\n".write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let app = root.appendingPathComponent("Example.app")
        let owner = ThirdPartyCaskSource.Ownership(token: "example", tap: "homebrew/cask", paths: [app.path], brewPrefix: "/usr/local")
        await LoginShellEnvironment.$homebrewVariablesOverride.withValue([:]) {
            await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                await HomebrewInstaller.$ownershipOverride.withValue([owner]) {
                    do {
                        try await HomebrewInstaller().fetch(caskToken: "example", app: app) { _ in }
                        Issue.record("foreign prefix fetch must be refused")
                    } catch { #expect(error is HomebrewInstaller.UnsupportedPrefix) }
                    do {
                        try await HomebrewInstaller().upgrade(caskToken: "example", app: app) { _ in }
                        Issue.record("foreign prefix apply must be refused")
                    } catch { #expect(error is HomebrewInstaller.UnsupportedPrefix) }
                }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test func batchChecksRefuseOverlappingForeignOwnersButKeepIndependentCopies() async throws {
        let selected = ThirdPartyCaskSource.Ownership(
            token: "example", tap: "homebrew/cask", paths: ["/Applications/Example.app"], brewPrefix: "/opt/homebrew")
        let foreign = ThirdPartyCaskSource.Ownership(
            token: "example", tap: "homebrew/cask", paths: ["/Applications/Example.app"], brewPrefix: "/usr/local")
        await HomebrewInstaller.$ownershipOverride.withValue([selected, foreign]) {
            do {
                try await HomebrewInstaller.validateCaskOwners(["example"], selectedBrew: "/opt/homebrew/bin/brew")
                Issue.record("overlapping foreign owner must refuse batch")
            } catch { #expect(error is HomebrewInstaller.UnsupportedPrefix) }
        }
        let separate = ThirdPartyCaskSource.Ownership(
            token: "example", tap: "homebrew/cask", paths: ["/Other/Example.app"], brewPrefix: "/usr/local")
        try await HomebrewInstaller.$ownershipOverride.withValue([selected, separate]) {
            try await HomebrewInstaller.validateCaskOwners(["example"], selectedBrew: "/opt/homebrew/bin/brew")
        }
    }

}
