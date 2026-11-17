import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct BrewCaskPackageEligibilityTests {
    private let info = Data(#"""
        {"casks":[
          {"token":"arm-package","tap":"homebrew/cask","installed":"1.0","version":"2.0",
           "depends_on":{"arch":[{"type":"arm","bits":64}],"macos":{">=":["15"]}}},
          {"token":"intel-package","tap":"homebrew/cask","installed":"1.0","version":"2.0",
           "depends_on":{"arch":[{"type":"intel","bits":64}]}},
          {"token":"old-os-package","tap":"homebrew/cask","installed":"1.0","version":"2.0",
           "depends_on":{"macos":{"==":["15","26"]}}}
        ]}
        """#.utf8)

    @Test(arguments: [false, true])
    func currentCaskRequirementsReachBothPackageFallbackKinds(hasAppRows: Bool) throws {
        let facts = Dictionary(uniqueKeysWithValues: ["arm-package", "intel-package", "old-os-package"].map {
            ($0, BrewFormulaService.CaskFacts(installsAnApp: hasAppRows,
                                             appPaths: hasAppRows ? ["/Applications/Fixture/\($0).app"] : [],
                                             needsSudo: true))
        })
        let inventory = hasAppRows
            ? BrewFormulaService.appCasks(installedInfo: info, facts: facts, osVersion: "27.2", hostArchitecture: .arm64).map(\.row)
            : BrewFormulaService.appLessCasks(installedInfo: info, facts: facts, osVersion: "27.2", hostArchitecture: .arm64)
        #expect(Set(inventory.map(\.name)) == ["arm-package", "intel-package", "old-os-package"])
        let updates = inventory.map {
            BrewOutdatedFormula(name: $0.name, installedVersion: "1.0", currentVersion: "2.0", kind: .cask)
        }
        let merged = BrewFormulaService.merge(inventory, outdated: updates)
        let arm = try #require(merged.first { $0.name == "arm-package" })
        let intel = try #require(merged.first { $0.name == "intel-package" })
        let oldOS = try #require(merged.first { $0.name == "old-os-package" })
        #expect(merged.allSatisfy { $0.hasUpdate })
        #expect(arm.canUpgrade)
        #expect(arm.incompatibility == nil)
        #expect(intel.incompatibility == .architecture(required: [.x86_64], host: .arm64))
        #expect(!intel.canUpgrade)
        #expect(oldOS.incompatibility == .macOS(
            required: CaskMacOSRequirement(comparison: .exactly, versions: ["15", "26"]), host: "27.2"))
        #expect(!oldOS.canUpgrade)
    }

    @Test func mergePreservesAllIndependentUpgradeRefusals() throws {
        let reason = CaskIncompatibility.architecture(required: [.x86_64], host: .arm64)
        let row = BrewInstalledFormula(
            name: "fixture", installedVersion: "1.0", availableVersion: nil, kind: .cask,
            needsSudo: true, manualInstaller: true, missingAppPath: "/Applications/Missing.app", incompatibility: reason)
        let merged = try #require(BrewFormulaService.merge([row], outdated: [
            BrewOutdatedFormula(name: "fixture", installedVersion: "1.0", currentVersion: "2.0", kind: .cask),
        ]).first)
        #expect(merged.availableVersion == "2.0")
        #expect(merged.needsSudo)
        #expect(merged.manualInstaller)
        #expect(merged.missingAppPath == "/Applications/Missing.app")
        #expect(merged.incompatibility == reason)
        #expect(!merged.canUpgrade)
    }
}
