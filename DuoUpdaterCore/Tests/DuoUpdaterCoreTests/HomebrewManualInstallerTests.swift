import Foundation
import Testing
@testable import DuoUpdaterCore

struct HomebrewManualInstallerTests {
    private func metadata(
        version: String = "2.0,3", path: String = "Install Fixture.app",
        dependencies: [String: Any] = [:]
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["casks": [[
            "token": "fixture", "tap": "homebrew/cask", "version": version,
            "artifacts": [["installer": [["manual": path]]]], "depends_on": dependencies,
        ]]])
    }

    @Test func planPinsVersionAndDeclaredPath() throws {
        let data = try metadata()
        #expect(try HomebrewManualInstaller.plan(
            from: data, token: "fixture", version: "2.0,3", path: "Install Fixture.app")
            == .init(token: "fixture", version: "2.0,3", path: "Install Fixture.app"))
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.plan(from: data, token: "fixture", version: "2.0,2", path: "Install Fixture.app")
        }
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.plan(from: data, token: "fixture", version: "2.0,3", path: "Other.app")
        }
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.plan(from: data, token: "different", version: "2.0,3", path: "Install Fixture.app")
        }
    }

    @Test func currentBrewRequirementsStillApply() throws {
        let data = try metadata(dependencies: ["macos": [">=": ["999"]]])
        #expect(throws: CaskIncompatibility.self) {
            try HomebrewManualInstaller.plan(from: data, token: "fixture", version: "2.0,3", path: "Install Fixture.app")
        }
    }

    @Test(arguments: ["/Applications/Fixture.app", "../Fixture.app", "folder/../Fixture.app", "folder//Fixture.app", "./Fixture.app", "Fixture.app/", "", "bad\0.app"])
    func unsafePathsAreRefused(path: String) throws {
        #expect(!HomebrewManualInstaller.isRelativeArtifactPath(path))
        let data = try metadata(path: path)
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.plan(from: data, token: "fixture", version: "2.0,3", path: path)
        }
    }

    @Test func extractedSymlinkCannotEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let stage = root.appendingPathComponent("stage")
        let outside = root.appendingPathComponent("Other.app")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: stage.appendingPathComponent("Install.app"), withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.artifact(in: stage, path: "Install.app")
        }
        let outsideRoot = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideRoot.appendingPathComponent("Install.app"), withIntermediateDirectories: true)
        let linkedRoot = root.appendingPathComponent("linked-stage")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outsideRoot)
        #expect(throws: (any Error).self) {
            try HomebrewManualInstaller.artifact(in: linkedRoot, path: "Install.app")
        }
        let inside = stage.appendingPathComponent("nested/Install.app")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        #expect(try HomebrewManualInstaller.artifact(in: stage, path: "nested/Install.app")
            == inside.standardizedFileURL.resolvingSymlinksInPath())
    }
}
