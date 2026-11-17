import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct BrewReadValidityTests {
    private static let info = #"{"formulae":[{"name":"zzfixture-tool","full_name":"zzfixture-tool","deprecated":true,"deprecation_reason":"unmaintained"}],"casks":[{"token":"zzfixture-cask","tap":"homebrew/cask","installed":"1.0","artifacts":[],"deprecated":true,"deprecation_reason":"unmaintained"}]}"#

    private static func service(
        failing: String? = nil, overrides: [String: String] = [:]
    ) -> BrewFormulaService {
        let output = [
            "leaves": "zzfixture-tool\n",
            "list --formula --versions": "zzfixture-tool 1.0\n",
            "list --formula --full-name": "zzfixture-tool\n",
            "info --json=v2 --installed": info,
            "formulae": "zzfixture-tool\n",
            "casks": "zzfixture-cask\n",
            "tap-info --json=v1 --installed": "[]",
            "outdated --formula --json=v2": #"{"formulae":[],"casks":[]}"#,
            "outdated --cask --json=v2": #"{"formulae":[],"casks":[]}"#,
        ].merging(overrides) { _, new in new }
        return BrewFormulaService(executor: { arguments in
            let key = arguments.joined(separator: " ")
            if key == failing { return (1, Data("controlled read failure".utf8)) }
            guard let value = output[key] else {
                Issue.record("unexpected read: \(key)")
                return (1, Data())
            }
            return (0, Data(value.utf8))
        }, caskReceiptTap: { _ in "zzfixture/tap" })
    }

    @Test func successfulEmptyJSONIsAValidVerdict() async throws {
        let service = Self.service(overrides: [
            "info --json=v2 --installed": #"{"formulae":[],"casks":[]}"#,
            "list --formula --full-name": "", "list --formula --versions": "", "leaves": "",
        ])
        #expect(try await service.installedLeaves().isEmpty)
        #expect(try await service.outdated().isEmpty)
        #expect(try await service.outdatedCasks().isEmpty)
        let report = await service.installedReport()
        #expect(report.casksRead && report.formulaeRead)
        #expect(report.uncheckedCasksRead && report.uncheckedFormulaeRead)
        #expect(report.appLessCasks.isEmpty && report.appCasks.isEmpty)
        #expect(report.readErrors.isEmpty)
    }

    @Test(arguments: ["not JSON", "{}", #"{"formulae":{},"casks":{}}"#])
    func malformedOutdatedDoesNotClearPreviousOffers(output: String) async {
        let service = Self.service(overrides: [
            "outdated --formula --json=v2": output,
            "outdated --cask --json=v2": output,
        ])
        await #expect(throws: BrewFormulaService.BrewError.self) { _ = try await service.outdated() }
        await #expect(throws: BrewFormulaService.BrewError.self) { _ = try await service.outdatedCasks() }
    }

    @Test func aFailedInfoReadMarksItsFactsUnavailable() async {
        let service = Self.service(failing: "info --json=v2 --installed")
        let report = await service.installedReport()
        #expect(!report.formulaeRead && !report.casksRead)
        #expect(!report.uncheckedFormulaeRead && !report.uncheckedCasksRead)
        #expect(report.readErrors.contains { $0.contains("controlled read failure") })
    }

    @Test func malformedFormulaInfoDoesNotDiscardTheCaskHalf() async {
        let service = Self.service(overrides: [
            "info --json=v2 --installed": #"{"formulae":{},"casks":[{"token":"zzfixture-cask","tap":"homebrew/cask","installed":"1.0","artifacts":[],"deprecated":true}]}"#,
        ])
        let report = await service.installedReport()
        #expect(!report.formulaeRead && !report.uncheckedFormulaeRead)
        #expect(report.casksRead && report.uncheckedCasksRead)
        #expect(report.appLessCasks.map(\.name) == ["zzfixture-cask"])
        #expect(report.caskLifecycles.map(\.token) == ["zzfixture-cask"])
        #expect(!report.readErrors.isEmpty)
    }

    @Test(arguments: ["list --formula --full-name", "list --formula --versions", "formulae", "casks"])
    func anAuxiliaryFailureRetainsFormulaWarningsOnly(command: String) async {
        let report = await Self.service(failing: command).installedReport()
        #expect(report.formulaeRead && report.casksRead)
        #expect(!report.uncheckedFormulaeRead && report.uncheckedCasksRead)
        #expect(report.lifecycles["zzfixture-tool"]?.stage == .deprecated)
        #expect(!report.readErrors.isEmpty)
    }

    @Test func aFailedTapReadDoesNotReplaceTrustedWarningsWithUnreadable() async {
        let service = Self.service(failing: "tap-info --json=v1 --installed", overrides: [
            "list --formula --full-name": "zzfixture/tap/tool\n",
            "info --json=v2 --installed": #"{"formulae":[],"casks":[{"token":"zzfixture-cask","tap":null,"installed":"1.0","artifacts":[]}]}"#,
        ])
        let report = await service.installedReport()
        #expect(report.formulaeRead && report.casksRead)
        #expect(!report.uncheckedFormulaeRead && !report.uncheckedCasksRead)
        #expect(Set(report.unchecked.map { $0.kind.rawValue }) == ["formula", "cask"])
        #expect(!report.readErrors.isEmpty)
    }

    @Test func aFailedVersionsReadIsNotAnEmptyLeafInventory() async {
        let service = Self.service(failing: "list --formula --versions", overrides: ["leaves": ""])
        await #expect(throws: BrewFormulaService.BrewError.self) { _ = try await service.installedLeaves() }
    }

    @Test func realExecutorKeepsFailureStderrOutOfSuccessfulJSON() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("brew-read")
        try Data("""
        #!/bin/sh
        if [ "$2" = --cask ]; then
          echo 'controlled stderr failure' >&2
          exit 7
        fi
        echo 'harmless warning' >&2
        echo '{"formulae":[],"casks":[]}'
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let service = BrewFormulaService(executor: BrewFormulaService.executor(brewPath: { script.path }))
        #expect(try await service.outdated().isEmpty)
        do {
            _ = try await service.outdatedCasks()
            Issue.record("a failed child must throw")
        } catch BrewFormulaService.BrewError.failed(let code, let output) {
            #expect(code == 7)
            #expect(output.contains("controlled stderr failure"))
        }
    }
}
